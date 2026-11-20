//! The `ke_io` contract over a `ke_file_system` with no thread of its own: each request runs on the
//! thread that submits it, before the submission returns, and is released by the `wait` that collects
//! it.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_io_inline").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const abi_part = @import("abi_part");
const part = @import("part");
const abi_completion = @import("abi_completion");
const abi_file_system = @import("abi_file_system");
const abi_io = @import("abi_io");
const abi_io_inline_factory = @import("abi_io_inline_factory");
const abi_result = @import("abi_result");
const abi_settings = @import("abi_settings");
const heap = @import("heap");
const settings_schema = @import("settings_schema");

const R = @import("result").Result(.{});
const log = std.log.scoped(.io_inline);

const bytes_header = 16;
const bytes_alignment: std.mem.Alignment = .@"16";

/// The allocation behind one handle. `api` is the vtable the handle's `ref` points at, and its
/// `handle` slot points back at this block. `file_system` is borrowed from the factory's arguments.
const State = struct {
    api: abi_io.c.ke_io,
    file_system: *abi_file_system.c.ke_file_system,
};

const Kind = enum { read_file, open, read_at, stat, file_exists };

/// One submitted request, allocated and run by `submit` and freed by `wait`; the `ke_io_request`
/// pointer is its address.
const Request = struct {
    state: *State,
    kind: Kind,
    path: ?[:0]u8,
    file: ?*abi_file_system.c.ke_open_file,
    offset: u64,
    dst: ?[*]u8,
    len: usize,
    completion: abi_completion.c.ke_completion,
    code: abi_result.c.ke_result,
    result: abi_io.c.ke_io_result,

    fn run(self: *Request) void {
        const code = switch (self.kind) {
            .read_file => self.readFile(),
            .open => self.openFile(),
            .read_at => self.readAt(),
            .stat => self.statPath(),
            .file_exists => self.askExists(),
        };
        if (code != R.ok) self.result = std.mem.zeroes(abi_io.c.ke_io_result);
        self.code = code;
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

fn requestOfCompletion(completion: ?*abi_completion.c.ke_completion) *Request {
    return @fieldParentPtr("completion", completion.?);
}

/// The completion's `poll`: the request ran when it was submitted, so it always reports finished.
fn completionPoll(completion: ?*abi_completion.c.ke_completion, out: ?*abi_result.c.ke_result) callconv(.c) bool {
    if (out) |o| o.* = requestOfCompletion(completion).code;
    return true;
}

/// The completion's `wait`: returns what the request finished with, without blocking.
fn completionWait(completion: ?*abi_completion.c.ke_completion) callconv(.c) abi_result.c.ke_result {
    return requestOfCompletion(completion).code;
}

/// The completion's `release`: the request owns its completion and `wait` of the ke_io frees both.
fn completionRelease(_: ?*abi_completion.c.ke_completion) callconv(.c) void {}

/// Allocates a request, copies `path` into it, and runs it. Fails as out of memory with nothing left
/// allocated when an allocation fails.
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
        .completion = .{ .handle = null, .poll = completionPoll, .wait = completionWait, .release = completionRelease },
        .code = R.ok,
        .result = std.mem.zeroes(abi_io.c.ke_io_result),
    };
    if (path) |p| request.path = heap.gpa.dupeZ(u8, std.mem.span(p)) catch {
        log.warn("submitting a {t} request failed: out of memory", .{kind});
        request.free();
        return R.code(error.OutOfMemory);
    };
    request.run();
    out.* = @ptrCast(request);
    return R.ok;
}

/// Slot `read_file`. The bytes are allocated by the operation once the size is known.
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
    _ = request;
    return true;
}

/// Slot `completion`: the request's own completion, which `wait` gives back.
fn completionOf(self_in: ?*abi_io.c.ke_io, request_in: ?*abi_io.c.ke_io_request) callconv(.c) ?*abi_completion.c.ke_completion {
    _ = self_in orelse return null;
    return &requestOf(request_in orelse return null).completion;
}

/// Slot `wait`. Copies the result of the request, which ran when it was submitted, out and frees it.
fn wait(self_in: ?*abi_io.c.ke_io, request_in: ?*abi_io.c.ke_io_request, out_result: ?*abi_io.c.ke_io_result) callconv(.c) abi_result.c.ke_result {
    _ = self_in orelse return R.code(error.InvalidArgument);
    if (out_result) |out| out.* = std.mem.zeroes(abi_io.c.ke_io_result);
    const request = requestOf(request_in orelse return R.code(error.InvalidArgument));
    const code = completionWait(&request.completion);
    if (out_result) |out| out.* = if (code == R.ok) request.result else std.mem.zeroes(abi_io.c.ke_io_result);
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

/// The handle's `destroy`. Frees the `State`; requests not yet waited on are not freed. A null ke_io
/// is ignored.
fn destroy(self_in: ?*abi_io.c.ke_io) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    heap.gpa.destroy(stateOf(self));
}

/// The io's settings: this implementation has none.
const Settings = struct {};

export fn ke_io_inline_create(file_system: ?*abi_file_system.c.ke_file_system, settings: ?*abi_settings.c.ke_settings, out_io: ?*abi_io.c.ke_io_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_io orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_io.c.ke_io_handle);
    out.* = create(file_system, settings) catch |err| {
        log.warn("creating the io failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

pub const parts = [_]abi_part.c.ke_part{
    part.of(ke_io_inline_create, .{ .name = "io_inline", .slots = &.{"file_system"}, .set_log = @ptrCast(&@import("log").Destination("ke_io_inline").setLogCallback) }),
};

/// The library's parts.
export fn ke_io_inline_parts(out_count: ?*usize) callconv(.c) ?*const abi_part.c.ke_part {
    if (out_count) |n| n.* = parts.len;
    return &parts[0];
}

fn create(file_system_in: ?*abi_file_system.c.ke_file_system, settings: ?*abi_settings.c.ke_settings) R.Error!abi_io.c.ke_io_handle {
    const file_system = file_system_in orelse return error.InvalidArgument;
    _ = try settings_schema.read(Settings, settings orelse return error.InvalidArgument);
    const s = heap.gpa.create(State) catch return error.OutOfMemory;
    s.* = .{ .api = std.mem.zeroes(abi_io.c.ke_io), .file_system = file_system };

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
    s.api.completion = completionOf;
    s.api.wait = wait;
    s.api.close = close;
    s.api.free_bytes = freeBytesSlot;

    return .{ .ref = &s.api, .destroy = destroy };
}

const testing = std.testing;
const zsub = @import("zsub");

const FileSystemSub = zsub.For(abi_file_system.c.ke_file_system);

const contents = "the quick brown fox jumps over the lazy dog";
var open_token: u8 = 0;
var opened_on: std.Thread.Id = 0;

fn openFox(args: FileSystemSub.Args(.open)) abi_result.c.ke_result {
    opened_on = std.Thread.getCurrentId();
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
    fs: FileSystemSub,
    handle: abi_io.c.ke_io_handle,

    fn init(self: *Rig) !void {
        try self.fs.init();
        errdefer self.fs.deinit();
        _ = self.fs.when(.open).does(openFox);
        _ = self.fs.when(.size).does(foxSize);
        _ = self.fs.when(.read_at).does(readFox);
        _ = self.fs.when(.stat).does(statFox);
        var none = settings_schema.Fixed.init(&.{});
        try R.check(ke_io_inline_create(self.fs.api(), &none.api, &self.handle));
    }

    fn io(self: *Rig) *abi_io.c.ke_io {
        return self.handle.ref.?;
    }

    fn request(self: *Rig, comptime slot: anytype, args: anytype) !*abi_io.c.ke_io_request {
        var out: ?*abi_io.c.ke_io_request = null;
        try R.check(@call(.auto, @field(self.io(), @tagName(slot)).?, .{self.io()} ++ args ++ .{&out}));
        return out.?;
    }

    fn deinit(self: *Rig) void {
        self.handle.destroy.?(self.handle.ref);
        self.fs.deinit();
    }
};

test "a whole-file read runs on the submitting thread and is finished before the submission returns" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    const request = try rig.request(.read_file, .{"fox.txt"});
    try testing.expectEqual(std.Thread.getCurrentId(), opened_on);
    try testing.expect(rig.io().is_completed.?(rig.io(), request));
    const completion = rig.io().completion.?(rig.io(), request).?;
    var code: abi_result.c.ke_result = R.code(error.General);
    try testing.expect(completion.poll.?(completion, &code));
    try R.check(code);

    var result: abi_io.c.ke_io_result = undefined;
    try R.check(rig.io().wait.?(rig.io(), request, &result));
    defer rig.io().free_bytes.?(rig.io(), result.bytes);
    try testing.expectEqualStrings(contents, @as([*]const u8, @ptrCast(result.bytes.?))[0..result.size]);
    try rig.fs.received(.close).sameAs(rig.fs.received(.open));
}

test "a whole-file read of a missing file fails as not found with a zeroed result" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    const request = try rig.request(.read_file, .{"missing.txt"});
    var result: abi_io.c.ke_io_result = undefined;
    try testing.expectError(error.NotFound, R.check(rig.io().wait.?(rig.io(), request, &result)));
    try testing.expect(result.bytes == null and result.size == 0);
}

test "an opened file is read at an offset, and stat and file_exists report what the path names" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    var result: abi_io.c.ke_io_result = undefined;
    try R.check(rig.io().wait.?(rig.io(), try rig.request(.open, .{"fox.txt"}), &result));
    const file = result.file.?;
    var buf: [16]u8 = undefined;
    try R.check(rig.io().wait.?(rig.io(), try rig.request(.read_at, .{ file, contents.len - 3, &buf, buf.len }), &result));
    try testing.expectEqualStrings("dog", buf[0..result.size]);
    rig.io().close.?(rig.io(), file);

    try R.check(rig.io().wait.?(rig.io(), try rig.request(.stat, .{"fox.txt"}), &result));
    try testing.expectEqual(@as(u64, contents.len), result.stat.size);
    try R.check(rig.io().wait.?(rig.io(), try rig.request(.file_exists, .{"missing.txt"}), &result));
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
}

test "submits with missing arguments are an invalid argument and a null request is refused by wait" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    var request: ?*abi_io.c.ke_io_request = null;
    try testing.expectError(error.InvalidArgument, R.check(rig.io().read_file.?(rig.io(), null, &request)));
    try testing.expectError(error.InvalidArgument, R.check(rig.io().read_at.?(rig.io(), null, 0, null, 0, &request)));
    try testing.expectError(error.InvalidArgument, R.check(rig.io().read_file.?(rig.io(), "fox.txt", null)));
    try testing.expect(request == null);
    try testing.expectError(error.InvalidArgument, R.check(rig.io().wait.?(rig.io(), null, null)));
}

test "creating without a file system or settings, or with any setting, is refused and leaves the handle zeroed" {
    var fs: FileSystemSub = undefined;
    try fs.init();
    defer fs.deinit();

    var none = settings_schema.Fixed.init(&.{});
    var some = settings_schema.Fixed.init(&.{.{ .key = "worker_count", .value = .{ .int = 1 } }});
    var h: abi_io.c.ke_io_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_io_inline_create(null, &none.api, &h)));
    try testing.expect(h.ref == null and h.destroy == null);
    try testing.expectError(error.InvalidArgument, R.check(ke_io_inline_create(fs.api(), null, &h)));
    try testing.expectError(error.InvalidArgument, R.check(ke_io_inline_create(fs.api(), &some.api, &h)));
    try testing.expectError(error.InvalidArgument, R.check(ke_io_inline_create(fs.api(), &none.api, null)));
}

test "the library's part is io_inline, built from its factory" {
    var count: usize = 0;
    const p = ke_io_inline_parts(&count).?;
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqualStrings("io_inline", std.mem.span(p.name.?));
    try std.testing.expectEqual(@as(usize, 1), p.provides_count);
    try std.testing.expectEqual(@as(usize, 1), p.slot_count);
}

test "reading, waiting, freeing and destroying leaves no block allocated" {
    var rig: Rig = undefined;
    try rig.init();
    var result: abi_io.c.ke_io_result = undefined;
    try R.check(rig.io().wait.?(rig.io(), try rig.request(.read_file, .{"fox.txt"}), &result));
    rig.io().free_bytes.?(rig.io(), result.bytes);
    rig.deinit();
    try heap.expectNoLeaks();
}
