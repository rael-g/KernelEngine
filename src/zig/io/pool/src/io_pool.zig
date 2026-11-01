//! The `ke_io` contract over a `ke_task_pool` and a `ke_file_system`: each request runs as one task
//! of the pool, reading through the file system, and is released by the `wait` that collects it.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_io_pool").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const abi_file_system = @import("abi_file_system");
const abi_io = @import("abi_io");
const abi_io_pool_factory = @import("abi_io_pool_factory");
const abi_result = @import("abi_result");
const abi_task_pool = @import("abi_task_pool");
const heap = @import("heap");

const R = @import("result").Result(.{});
const log = std.log.scoped(.io_pool);

const bytes_header = 16;
const bytes_alignment: std.mem.Alignment = .@"16";

/// The allocation behind one handle. `api` is the vtable the handle's `ref` points at, and its
/// `handle` slot points back at this block. `task_pool` and `file_system` are borrowed from the
/// factory's arguments and never released here.
const State = struct {
    api: abi_io.c.ke_io,
    task_pool: *abi_task_pool.c.ke_task_pool,
    file_system: *abi_file_system.c.ke_file_system,
};

const Kind = enum { read_file, open, read_at, stat, file_exists };

/// One submitted request, allocated by `submit` and freed by `wait`; the `ke_io_request` pointer is
/// its address. The task writes `code` and `result` and then stores `completed`, so a thread that
/// reads `completed` as true reads them as written.
const Request = struct {
    state: *State,
    kind: Kind,
    path: ?[:0]u8,
    file: ?*abi_file_system.c.ke_open_file,
    offset: u64,
    dst: ?[*]u8,
    len: usize,
    task: ?*abi_task_pool.c.ke_task,
    code: abi_result.c.ke_result,
    result: abi_io.c.ke_io_result,
    completed: std.atomic.Value(bool),

    fn run(self: *Request) void {
        self.code = switch (self.kind) {
            .read_file => self.readFile(),
            .open => self.openFile(),
            .read_at => self.readAt(),
            .stat => self.statPath(),
            .file_exists => self.askExists(),
        };
        if (self.code != R.ok) self.result = std.mem.zeroes(abi_io.c.ke_io_result);
        self.completed.store(true, .release);
    }

    fn readFile(self: *Request) abi_result.c.ke_result {
        const fs = self.state.file_system;
        var file: ?*abi_file_system.c.ke_open_file = null;
        const opened = fs.open.?(fs, self.path.?.ptr, &file);
        if (opened != R.ok) return opened;
        defer fs.close.?(fs, file);

        var size: u64 = 0;
        const sized = fs.size.?(fs, file, &size);
        if (sized != R.ok) return sized;
        const len = std.math.cast(usize, size) orelse return R.code(error.OutOfMemory);
        const bytes = allocBytes(len) orelse return R.code(error.OutOfMemory);

        var read: usize = 0;
        const code = fs.read_at.?(fs, file, 0, bytes, len, &read);
        if (code != R.ok) {
            freeBytes(bytes);
            return code;
        }
        self.result.bytes = bytes;
        self.result.size = read;
        return R.ok;
    }

    fn openFile(self: *Request) abi_result.c.ke_result {
        const fs = self.state.file_system;
        return fs.open.?(fs, self.path.?.ptr, &self.result.file);
    }

    fn readAt(self: *Request) abi_result.c.ke_result {
        const fs = self.state.file_system;
        var read: usize = 0;
        const code = fs.read_at.?(fs, self.file, self.offset, self.dst, self.len, &read);
        self.result.size = read;
        return code;
    }

    fn statPath(self: *Request) abi_result.c.ke_result {
        const fs = self.state.file_system;
        return fs.stat.?(fs, self.path.?.ptr, &self.result.stat);
    }

    fn askExists(self: *Request) abi_result.c.ke_result {
        const fs = self.state.file_system;
        var st: abi_file_system.c.ke_file_stat = undefined;
        R.check(fs.stat.?(fs, self.path.?.ptr, &st)) catch |err| switch (err) {
            error.NotFound => return R.ok,
            else => return R.code(err),
        };
        self.result.exists = st.kind == abi_file_system.c.KE_FILE_KIND_FILE;
        return R.ok;
    }

    fn free(self: *Request) void {
        if (self.path) |p| heap.gpa.free(p);
        heap.gpa.destroy(self);
    }
};

fn stateOf(self: *abi_io.c.ke_io) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn requestOf(request: *abi_io.c.ke_io_request) *Request {
    return @ptrCast(@alignCast(request));
}

/// Allocates `len` bytes behind a header that records `len`, so `freeBytes` can release them from
/// the pointer alone.
fn allocBytes(len: usize) ?[*]u8 {
    const total = std.math.add(usize, len, bytes_header) catch return null;
    const block = heap.gpa.alignedAlloc(u8, bytes_alignment, total) catch return null;
    std.mem.writeInt(usize, block[0..@sizeOf(usize)], len, .little);
    return block.ptr + bytes_header;
}

fn freeBytes(bytes: [*]u8) void {
    const base: [*]align(16) u8 = @alignCast(bytes - bytes_header);
    const len = std.mem.readInt(usize, base[0..@sizeOf(usize)], .little);
    heap.gpa.free(base[0 .. len + bytes_header]);
}

fn taskRun(data: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    const request: *Request = @ptrCast(@alignCast(data orelse return R.code(error.InvalidArgument)));
    request.run();
    return request.code;
}

/// Allocates a request, copies `path` into it, and dispatches it on the task pool. Returns null
/// with nothing left allocated when an allocation or the dispatch fails.
fn submit(self: *abi_io.c.ke_io, kind: Kind, path: ?[*:0]const u8, file: ?*abi_file_system.c.ke_open_file, offset: u64, dst: ?[*]u8, len: usize, out: *?*abi_io.c.ke_io_request) abi_result.c.ke_result {
    const s = stateOf(self);
    const request = heap.gpa.create(Request) catch {
        log.warn("submitting a {t} request failed: out of memory", .{kind});
        return R.code(error.OutOfMemory);
    };
    request.* = .{
        .state = s,
        .kind = kind,
        .path = null,
        .file = file,
        .offset = offset,
        .dst = dst,
        .len = len,
        .task = null,
        .code = R.ok,
        .result = std.mem.zeroes(abi_io.c.ke_io_result),
        .completed = .init(false),
    };
    if (path) |p| request.path = heap.gpa.dupeZ(u8, std.mem.span(p)) catch {
        log.warn("submitting a {t} request failed: out of memory", .{kind});
        request.free();
        return R.code(error.OutOfMemory);
    };
    R.check(s.task_pool.dispatch.?(s.task_pool, taskRun, request, &request.task)) catch |err| {
        log.warn("submitting a {t} request failed: the task pool refused it: {t}", .{ kind, err });
        request.free();
        return R.code(err);
    };
    out.* = @ptrCast(request);
    return R.ok;
}

/// Slot `read_file`. The bytes are allocated by the task once the size is known.
fn readFile(self_in: ?*abi_io.c.ke_io, path: ?[*:0]const u8, out_request: ?*?*abi_io.c.ke_io_request) callconv(.c) abi_result.c.ke_result {
    const out = out_request orelse return R.code(error.InvalidArgument);
    out.* = null;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (path == null) return R.code(error.InvalidArgument);
    return submit(self, .read_file, path, null, 0, null, 0, out);
}

/// Slot `open`.
fn open(self_in: ?*abi_io.c.ke_io, path: ?[*:0]const u8, out_request: ?*?*abi_io.c.ke_io_request) callconv(.c) abi_result.c.ke_result {
    const out = out_request orelse return R.code(error.InvalidArgument);
    out.* = null;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (path == null) return R.code(error.InvalidArgument);
    return submit(self, .open, path, null, 0, null, 0, out);
}

/// Slot `read_at`.
fn readAt(self_in: ?*abi_io.c.ke_io, file: ?*abi_file_system.c.ke_open_file, offset: u64, dst: ?*anyopaque, len: usize, out_request: ?*?*abi_io.c.ke_io_request) callconv(.c) abi_result.c.ke_result {
    const out = out_request orelse return R.code(error.InvalidArgument);
    out.* = null;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (file == null or (dst == null and len != 0)) return R.code(error.InvalidArgument);
    return submit(self, .read_at, null, file, offset, @ptrCast(dst), len, out);
}

/// Slot `stat`.
fn stat(self_in: ?*abi_io.c.ke_io, path: ?[*:0]const u8, out_request: ?*?*abi_io.c.ke_io_request) callconv(.c) abi_result.c.ke_result {
    const out = out_request orelse return R.code(error.InvalidArgument);
    out.* = null;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (path == null) return R.code(error.InvalidArgument);
    return submit(self, .stat, path, null, 0, null, 0, out);
}

/// Slot `file_exists`.
fn fileExists(self_in: ?*abi_io.c.ke_io, path: ?[*:0]const u8, out_request: ?*?*abi_io.c.ke_io_request) callconv(.c) abi_result.c.ke_result {
    const out = out_request orelse return R.code(error.InvalidArgument);
    out.* = null;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (path == null) return R.code(error.InvalidArgument);
    return submit(self, .file_exists, path, null, 0, null, 0, out);
}

/// Slots `dir_exists`, `list_dir`, `write_file`, `make_dir`, `remove` and `rename`: not provided,
/// since `ke_file_system` has no primitive for them; each writes no request and fails as not
/// supported.
fn unsupported(comptime name: []const u8, out_request: ?*?*abi_io.c.ke_io_request) abi_result.c.ke_result {
    const out = out_request orelse return R.code(error.InvalidArgument);
    out.* = null;
    log.warn(name ++ " is not supported", .{});
    return R.code(error.NotSupported);
}

fn dirExists(_: ?*abi_io.c.ke_io, _: ?[*:0]const u8, out_request: ?*?*abi_io.c.ke_io_request) callconv(.c) abi_result.c.ke_result {
    return unsupported("dir_exists", out_request);
}

fn listDir(_: ?*abi_io.c.ke_io, _: ?[*:0]const u8, out_request: ?*?*abi_io.c.ke_io_request) callconv(.c) abi_result.c.ke_result {
    return unsupported("list_dir", out_request);
}

fn writeFile(_: ?*abi_io.c.ke_io, _: ?[*:0]const u8, _: ?*const anyopaque, _: usize, out_request: ?*?*abi_io.c.ke_io_request) callconv(.c) abi_result.c.ke_result {
    return unsupported("write_file", out_request);
}

fn makeDir(_: ?*abi_io.c.ke_io, _: ?[*:0]const u8, out_request: ?*?*abi_io.c.ke_io_request) callconv(.c) abi_result.c.ke_result {
    return unsupported("make_dir", out_request);
}

fn remove(_: ?*abi_io.c.ke_io, _: ?[*:0]const u8, out_request: ?*?*abi_io.c.ke_io_request) callconv(.c) abi_result.c.ke_result {
    return unsupported("remove", out_request);
}

fn rename(_: ?*abi_io.c.ke_io, _: ?[*:0]const u8, _: ?[*:0]const u8, out_request: ?*?*abi_io.c.ke_io_request) callconv(.c) abi_result.c.ke_result {
    return unsupported("rename", out_request);
}

/// Slot `free_entries`: list_dir reports no entries, so there is nothing to release.
fn freeEntries(_: ?*abi_io.c.ke_io, _: ?*abi_io.c.ke_io_dir_entry) callconv(.c) void {}

/// Slot `is_completed`. A null request reports true.
fn isCompleted(self_in: ?*abi_io.c.ke_io, request_in: ?*abi_io.c.ke_io_request) callconv(.c) bool {
    _ = self_in;
    const request = request_in orelse return true;
    return requestOf(request).completed.load(.acquire);
}

/// Slot `wait`. Waits on the request's task, which leaves the request finished, then copies its
/// result out and frees it. When the task pool refuses the calling thread as not supported, that
/// code is returned and the request is left to be waited on again.
fn wait(self_in: ?*abi_io.c.ke_io, request_in: ?*abi_io.c.ke_io_request, out_result: ?*abi_io.c.ke_io_result) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (out_result) |out| out.* = std.mem.zeroes(abi_io.c.ke_io_result);
    const request = requestOf(request_in orelse return R.code(error.InvalidArgument));
    const s = stateOf(self);

    R.check(s.task_pool.wait.?(s.task_pool, request.task)) catch |err| switch (err) {
        error.NotSupported => {
            log.warn("wait refused: the task pool does not accept the calling thread", .{});
            return R.code(err);
        },
        else => {},
    };
    const code = request.code;
    if (out_result) |out| out.* = request.result;
    request.free();
    return code;
}

/// Slot `close`.
fn close(self_in: ?*abi_io.c.ke_io, file: ?*abi_file_system.c.ke_open_file) callconv(.c) void {
    const self = self_in orelse return;
    if (file == null) return;
    const fs = stateOf(self).file_system;
    fs.close.?(fs, file);
}

/// Slot `free_bytes`.
fn freeBytesSlot(self_in: ?*abi_io.c.ke_io, bytes: ?*anyopaque) callconv(.c) void {
    _ = self_in orelse return;
    freeBytes(@ptrCast(bytes orelse return));
}

/// The handle's `destroy`. Frees the `State`; requests not yet waited on are not freed. A null
/// ke_io is ignored.
fn destroy(self_in: ?*abi_io.c.ke_io) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    heap.gpa.destroy(stateOf(self));
}

/// The factory. Both the task pool and the file system are required; either missing is an invalid
/// argument. Fails with out of memory when the `State` cannot be allocated, leaving
/// the handle zeroed.
export fn ke_io_pool_create(task_pool: ?*abi_task_pool.c.ke_task_pool, file_system: ?*abi_file_system.c.ke_file_system, out_io: ?*abi_io.c.ke_io_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_io orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_io.c.ke_io_handle);
    out.* = create(task_pool, file_system) catch |err| {
        log.warn("creating the io failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn create(task_pool: ?*abi_task_pool.c.ke_task_pool, file_system: ?*abi_file_system.c.ke_file_system) R.Error!abi_io.c.ke_io_handle {
    const s = heap.gpa.create(State) catch return error.OutOfMemory;
    errdefer heap.gpa.destroy(s);
    s.* = .{
        .api = std.mem.zeroes(abi_io.c.ke_io),
        .task_pool = task_pool orelse return error.InvalidArgument,
        .file_system = file_system orelse return error.InvalidArgument,
    };

    s.api.handle = s;
    s.api.read_file = readFile;
    s.api.open = open;
    s.api.read_at = readAt;
    s.api.stat = stat;
    s.api.file_exists = fileExists;
    s.api.dir_exists = dirExists;
    s.api.list_dir = listDir;
    s.api.write_file = writeFile;
    s.api.make_dir = makeDir;
    s.api.remove = remove;
    s.api.rename = rename;
    s.api.free_entries = freeEntries;
    s.api.is_completed = isCompleted;
    s.api.wait = wait;
    s.api.close = close;
    s.api.free_bytes = freeBytesSlot;

    return .{ .ref = &s.api, .destroy = destroy };
}

const testing = std.testing;
const zsub = @import("zsub");

const TaskPoolSub = zsub.For(abi_task_pool.c.ke_task_pool);
const FileSystemSub = zsub.For(abi_file_system.c.ke_file_system);

const contents = "the quick brown fox jumps over the lazy dog";
var open_token: u8 = 0;
var task_token: u8 = 0;

fn runInline(args: TaskPoolSub.Args(.dispatch)) abi_result.c.ke_result {
    _ = args[1].?(args[2]);
    args[3].?.* = @ptrCast(&task_token);
    return R.ok;
}

fn refuseDispatch(args: TaskPoolSub.Args(.dispatch)) abi_result.c.ke_result {
    args[3].?.* = null;
    return R.code(error.NotSupported);
}

fn openFox(args: FileSystemSub.Args(.open)) abi_result.c.ke_result {
    if (!std.mem.eql(u8, std.mem.span(args[1].?), "fox.txt")) return R.code(error.NotFound);
    args[2].?.* = @ptrCast(&open_token);
    return R.ok;
}

fn foxSize(args: FileSystemSub.Args(.size)) abi_result.c.ke_result {
    args[2].?.* = contents.len;
    return R.ok;
}

fn readFox(args: FileSystemSub.Args(.read_at)) abi_result.c.ke_result {
    const offset: usize = @intCast(@min(args[2], contents.len));
    const n = @min(args[4], contents.len - offset);
    if (n > 0) @memcpy(@as([*]u8, @ptrCast(args[3].?))[0..n], contents[offset..][0..n]);
    args[5].?.* = n;
    return R.ok;
}

fn statFox(args: FileSystemSub.Args(.stat)) abi_result.c.ke_result {
    if (!std.mem.eql(u8, std.mem.span(args[1].?), "fox.txt")) return R.code(error.NotFound);
    args[2].?.* = .{ .kind = abi_file_system.c.KE_FILE_KIND_FILE, .size = contents.len };
    return R.ok;
}

const Rig = struct {
    pool: TaskPoolSub,
    fs: FileSystemSub,
    handle: abi_io.c.ke_io_handle,

    fn init(self: *Rig) !void {
        try self.pool.init();
        errdefer self.pool.deinit();
        try self.fs.init();
        errdefer self.fs.deinit();
        _ = self.pool.when(.dispatch).does(runInline);
        _ = self.fs.when(.open).does(openFox);
        _ = self.fs.when(.size).does(foxSize);
        _ = self.fs.when(.read_at).does(readFox);
        _ = self.fs.when(.stat).does(statFox);
        try R.check(ke_io_pool_create(self.pool.api(), self.fs.api(), &self.handle));
    }

    fn io(self: *Rig) *abi_io.c.ke_io {
        return self.handle.ref.?;
    }

    fn readFile(self: *Rig, path: [*:0]const u8) !*abi_io.c.ke_io_request {
        var request: ?*abi_io.c.ke_io_request = null;
        try R.check(self.io().read_file.?(self.io(), path, &request));
        return request.?;
    }

    fn open(self: *Rig, path: [*:0]const u8) !*abi_io.c.ke_io_request {
        var request: ?*abi_io.c.ke_io_request = null;
        try R.check(self.io().open.?(self.io(), path, &request));
        return request.?;
    }

    fn readAt(self: *Rig, file: ?*abi_file_system.c.ke_open_file, offset: u64, dst: []u8) !*abi_io.c.ke_io_request {
        var request: ?*abi_io.c.ke_io_request = null;
        try R.check(self.io().read_at.?(self.io(), file, offset, dst.ptr, dst.len, &request));
        return request.?;
    }

    fn fileExists(self: *Rig, path: [*:0]const u8) !*abi_io.c.ke_io_request {
        var request: ?*abi_io.c.ke_io_request = null;
        try R.check(self.io().file_exists.?(self.io(), path, &request));
        return request.?;
    }

    fn stat(self: *Rig, path: [*:0]const u8) !*abi_io.c.ke_io_request {
        var request: ?*abi_io.c.ke_io_request = null;
        try R.check(self.io().stat.?(self.io(), path, &request));
        return request.?;
    }

    fn deinit(self: *Rig) void {
        self.handle.destroy.?(self.handle.ref);
        self.fs.deinit();
        self.pool.deinit();
    }
};

test "a whole-file read runs on the task pool and hands the bytes to the caller" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    const request = try rig.readFile("fox.txt");
    try testing.expect(rig.io().is_completed.?(rig.io(), request));
    var result: abi_io.c.ke_io_result = undefined;
    try R.check(rig.io().wait.?(rig.io(), request, &result));
    defer rig.io().free_bytes.?(rig.io(), result.bytes);

    try testing.expectEqualStrings(contents, @as([*]const u8, @ptrCast(result.bytes.?))[0..result.size]);
    try rig.pool.received(.dispatch).times(1);
    try rig.pool.received(.wait).times(1);
    try rig.fs.received(.close).sameAs(rig.fs.received(.open));
}

test "a whole-file read of a missing file fails as not found with a zeroed result" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    const request = try rig.readFile("missing.txt");
    var result: abi_io.c.ke_io_result = undefined;
    try testing.expectError(error.NotFound, R.check(rig.io().wait.?(rig.io(), request, &result)));
    try testing.expect(result.bytes == null and result.size == 0);
    try rig.fs.received(.close).never();
}

test "an opened file is read at an offset into the caller's buffer and closed" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    var result: abi_io.c.ke_io_result = undefined;
    try R.check(rig.io().wait.?(rig.io(), try rig.open("fox.txt"), &result));
    const file = result.file.?;

    var buf: [16]u8 = undefined;
    try R.check(rig.io().wait.?(rig.io(), try rig.readAt(file, contents.len - 3, &buf), &result));
    try testing.expectEqualStrings("dog", buf[0..result.size]);

    rig.io().close.?(rig.io(), file);
    try rig.fs.received(.close).times(1);
}

test "stat reports what the path names" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    var result: abi_io.c.ke_io_result = undefined;
    try R.check(rig.io().wait.?(rig.io(), try rig.stat("fox.txt"), &result));
    try testing.expectEqual(abi_file_system.c.KE_FILE_KIND_FILE, result.stat.kind);
    try testing.expectEqual(@as(u64, contents.len), result.stat.size);
}

var pool_refuses_wait = false;

fn waitUnlessRefused(_: TaskPoolSub.Args(.wait)) abi_result.c.ke_result {
    return if (pool_refuses_wait) R.code(error.NotSupported) else R.ok;
}

test "a wait the task pool refuses for its calling thread fails and leaves the request waitable" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.pool.when(.wait).does(waitUnlessRefused);

    const request = try rig.readFile("fox.txt");

    var result: abi_io.c.ke_io_result = undefined;
    pool_refuses_wait = true;
    try testing.expectError(error.NotSupported, R.check(rig.io().wait.?(rig.io(), request, &result)));

    pool_refuses_wait = false;
    try R.check(rig.io().wait.?(rig.io(), request, &result));
    defer rig.io().free_bytes.?(rig.io(), result.bytes);
    try testing.expectEqual(@as(u64, contents.len), result.size);
}

test "a file that exists is reported as existing and a missing one as not, without a failure" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    var result: abi_io.c.ke_io_result = undefined;
    try R.check(rig.io().wait.?(rig.io(), try rig.fileExists("fox.txt"), &result));
    try testing.expect(result.exists);
    try R.check(rig.io().wait.?(rig.io(), try rig.fileExists("missing.txt"), &result));
    try testing.expect(!result.exists);
}

test "dir_exists, list_dir, write_file, make_dir, remove and rename are not supported and return no request" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    const io = rig.io();
    var request: ?*abi_io.c.ke_io_request = null;
    try testing.expectError(error.NotSupported, R.check(io.dir_exists.?(io, "dir", &request)));
    try testing.expectError(error.NotSupported, R.check(io.list_dir.?(io, "dir", &request)));
    try testing.expectError(error.NotSupported, R.check(io.write_file.?(io, "fox.txt", contents.ptr, contents.len, &request)));
    try testing.expectError(error.NotSupported, R.check(io.make_dir.?(io, "dir", &request)));
    try testing.expectError(error.NotSupported, R.check(io.remove.?(io, "fox.txt", &request)));
    try testing.expectError(error.NotSupported, R.check(io.rename.?(io, "fox.txt", "dog.txt", &request)));
    try testing.expect(request == null);
    try rig.pool.received(.dispatch).never();
}

test "a request the task pool refuses fails with the pool's code and returns no request" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.pool.when(.dispatch).does(refuseDispatch);

    var request: ?*abi_io.c.ke_io_request = null;
    try testing.expectError(error.NotSupported, R.check(rig.io().read_file.?(rig.io(), "fox.txt", &request)));
    try testing.expect(request == null);
}

test "submits with missing arguments are an invalid argument and a null request is refused by wait" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    var buf: [4]u8 = undefined;
    var request: ?*abi_io.c.ke_io_request = null;
    try testing.expectError(error.InvalidArgument, R.check(rig.io().read_file.?(rig.io(), null, &request)));
    try testing.expectError(error.InvalidArgument, R.check(rig.io().open.?(rig.io(), null, &request)));
    try testing.expectError(error.InvalidArgument, R.check(rig.io().stat.?(rig.io(), null, &request)));
    try testing.expectError(error.InvalidArgument, R.check(rig.io().file_exists.?(rig.io(), null, &request)));
    try testing.expectError(error.InvalidArgument, R.check(rig.io().read_at.?(rig.io(), null, 0, &buf, buf.len, &request)));
    try testing.expectError(error.InvalidArgument, R.check(rig.io().read_at.?(rig.io(), @ptrCast(&open_token), 0, null, 4, &request)));
    try testing.expectError(error.InvalidArgument, R.check(rig.io().read_file.?(rig.io(), "fox.txt", null)));
    try testing.expect(request == null);
    try testing.expectError(error.InvalidArgument, R.check(readFile(null, "fox.txt", &request)));
    try testing.expectError(error.InvalidArgument, R.check(rig.io().wait.?(rig.io(), null, null)));
    rig.io().close.?(rig.io(), null);
    rig.io().free_bytes.?(rig.io(), null);
    try rig.pool.received(.dispatch).never();
}

test "creating without a task pool or a file system is refused and leaves the handle zeroed" {
    var fs: FileSystemSub = undefined;
    try fs.init();
    defer fs.deinit();

    var h: abi_io.c.ke_io_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_io_pool_create(null, fs.api(), &h)));
    try testing.expect(h.ref == null and h.destroy == null);
    try testing.expectError(error.InvalidArgument, R.check(ke_io_pool_create(null, null, &h)));
    try testing.expectError(error.InvalidArgument, R.check(ke_io_pool_create(null, fs.api(), null)));
}

test "reading, waiting, freeing and destroying leaves no block allocated" {
    var rig: Rig = undefined;
    try rig.init();
    var result: abi_io.c.ke_io_result = undefined;
    try R.check(rig.io().wait.?(rig.io(), try rig.readFile("fox.txt"), &result));
    rig.io().free_bytes.?(rig.io(), result.bytes);
    rig.deinit();
    try heap.expectNoLeaks();
}
