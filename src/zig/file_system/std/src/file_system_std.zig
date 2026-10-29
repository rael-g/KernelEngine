//! The `ke_file_system` contract over the operating system's files, through `std.Io` on a
//! single-threaded instance that starts no thread: every slot blocks the thread that calls it.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_file_system_std").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const abi_file_system = @import("abi_file_system");
const abi_file_system_std_factory = @import("abi_file_system_std_factory");
const abi_result = @import("abi_result");
const heap = @import("heap");

const R = @import("result").Result(.{});
const log = std.log.scoped(.file_system_std);

/// The allocation behind one handle. `api` is the vtable the handle's `ref` points at, and its
/// `handle` slot points back at this block. `threaded` is the `std.Io` every slot goes through;
/// `root` resolves relative paths and is closed by `destroy` when `owns_root` says the factory
/// opened it.
const State = struct {
    api: abi_file_system.ke_file_system,
    threaded: std.Io.Threaded,
    root: std.Io.Dir,
    owns_root: bool,

    fn io(self: *State) std.Io {
        return self.threaded.io();
    }
};

/// One file `open` handed out, freed by `close`; the `ke_open_file` pointer is its address.
const OpenFile = struct {
    file: std.Io.File,
};

fn stateOf(self: *abi_file_system.ke_file_system) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn openFileOf(file: *abi_file_system.ke_open_file) *OpenFile {
    return @ptrCast(@alignCast(file));
}

/// Slot `open`. Allocates the `OpenFile` only once the file is open, so a failure leaves nothing
/// allocated and `out_file` null.
fn open(self_in: ?*abi_file_system.ke_file_system, path_in: ?[*:0]const u8, out_file: ?*?*abi_file_system.ke_open_file) callconv(.c) abi_result.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    const out = out_file orelse return R.code(error.InvalidArgument);
    out.* = null;
    const path = path_in orelse return R.code(error.InvalidArgument);
    const s = stateOf(self);

    const file = s.root.openFile(s.io(), std.mem.span(path), .{}) catch |err| {
        log.warn("opening {s} failed: {t}", .{ path, err });
        return R.code(if (err == error.FileNotFound) error.NotFound else error.Io);
    };
    const open_file = heap.gpa.create(OpenFile) catch {
        file.close(s.io());
        log.warn("opening {s} failed: out of memory", .{path});
        return R.code(error.OutOfMemory);
    };
    open_file.* = .{ .file = file };
    out.* = @ptrCast(open_file);
    return R.ok;
}

/// Slot `size`.
fn size(self_in: ?*abi_file_system.ke_file_system, file_in: ?*abi_file_system.ke_open_file, out_size: ?*u64) callconv(.c) abi_result.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    const file = file_in orelse return R.code(error.InvalidArgument);
    const out = out_size orelse return R.code(error.InvalidArgument);
    const s = stateOf(self);

    out.* = openFileOf(file).file.length(s.io()) catch |err| {
        log.warn("reading the size of a file failed: {t}", .{err});
        return R.code(error.Io);
    };
    return R.ok;
}

/// Slot `read_at`. Reads until `len` bytes or the end of the file, through positional reads that
/// move no shared cursor.
fn readAt(self_in: ?*abi_file_system.ke_file_system, file_in: ?*abi_file_system.ke_open_file, offset: u64, dst: ?*anyopaque, len: usize, out_read: ?*usize) callconv(.c) abi_result.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    const file = file_in orelse return R.code(error.InvalidArgument);
    const out = out_read orelse return R.code(error.InvalidArgument);
    out.* = 0;
    if (len == 0) return R.ok;
    const bytes: [*]u8 = @ptrCast(dst orelse return R.code(error.InvalidArgument));
    const s = stateOf(self);

    out.* = openFileOf(file).file.readPositionalAll(s.io(), bytes[0..len], offset) catch |err| {
        log.warn("reading a file at {d} failed: {t}", .{ offset, err });
        return R.code(error.Io);
    };
    return R.ok;
}

/// Slot `close`.
fn close(self_in: ?*abi_file_system.ke_file_system, file_in: ?*abi_file_system.ke_open_file) callconv(.c) void {
    const self = self_in orelse return;
    const file = file_in orelse return;
    const open_file = openFileOf(file);
    open_file.file.close(stateOf(self).io());
    heap.gpa.destroy(open_file);
}

/// Slot `stat`. A path that names neither a file nor a directory reports `KE_FILE_KIND_OTHER`.
fn stat(self_in: ?*abi_file_system.ke_file_system, path_in: ?[*:0]const u8, out_stat: ?*abi_file_system.ke_file_stat) callconv(.c) abi_result.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    const path = path_in orelse return R.code(error.InvalidArgument);
    const out = out_stat orelse return R.code(error.InvalidArgument);
    const s = stateOf(self);

    const st = s.root.statFile(s.io(), std.mem.span(path), .{}) catch |err| {
        if (err == error.FileNotFound) return R.code(error.NotFound);
        log.warn("inspecting {s} failed: {t}", .{ path, err });
        return R.code(error.Io);
    };
    out.* = .{
        .kind = switch (st.kind) {
            .file => abi_file_system.KE_FILE_KIND_FILE,
            .directory => abi_file_system.KE_FILE_KIND_DIRECTORY,
            else => abi_file_system.KE_FILE_KIND_OTHER,
        },
        .size = st.size,
    };
    return R.ok;
}

/// The handle's `destroy`. Closes the root when the factory opened it and frees the `State`;
/// files still open are not closed. A null file system is ignored.
fn destroy(self_in: ?*abi_file_system.ke_file_system) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    if (s.owns_root) s.root.close(s.io());
    heap.gpa.destroy(s);
}

/// The factory. A null `root`, or no params, resolves relative paths against the working
/// directory; any other root is opened once here. Fails with not found when the root names no
/// directory, out of memory when the `State` cannot be allocated and io otherwise, leaving
/// nothing allocated and the handle zeroed.
export fn ke_file_system_std_create(params_in: ?*const abi_file_system_std_factory.ke_file_system_std_params, out_file_system: ?*abi_file_system.ke_file_system_handle) callconv(.c) abi_result.ke_result {
    const out = out_file_system orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_file_system.ke_file_system_handle);
    out.* = create(params_in) catch |err| {
        log.warn("creating the file system failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn create(params_in: ?*const abi_file_system_std_factory.ke_file_system_std_params) R.Error!abi_file_system.ke_file_system_handle {
    const s = heap.gpa.create(State) catch return error.OutOfMemory;
    errdefer heap.gpa.destroy(s);
    s.* = .{
        .api = std.mem.zeroes(abi_file_system.ke_file_system),
        .threaded = .init_single_threaded,
        .root = std.Io.Dir.cwd(),
        .owns_root = false,
    };

    if (params_in) |p| if (p.root) |root| {
        s.root = std.Io.Dir.cwd().openDir(s.io(), std.mem.span(root), .{}) catch |err|
            return if (err == error.FileNotFound or err == error.NotDir) error.NotFound else error.Io;
        s.owns_root = true;
    };

    s.api.handle = s;
    s.api.open = open;
    s.api.size = size;
    s.api.read_at = readAt;
    s.api.close = close;
    s.api.stat = stat;

    return .{ .ref = &s.api, .destroy = destroy };
}

const testing = std.testing;

const contents = "the quick brown fox jumps over the lazy dog";

const Rig = struct {
    dir: testing.TmpDir,
    path: [std.fs.max_path_bytes]u8,
    handle: abi_file_system.ke_file_system_handle,

    fn init(self: *Rig) !void {
        self.dir = testing.tmpDir(.{});
        errdefer self.dir.cleanup();
        try self.dir.dir.writeFile(testing.io, .{ .sub_path = "fox.txt", .data = contents });
        try self.dir.dir.createDir(testing.io, "sub", .default_dir);
        const p = try std.fmt.bufPrint(&self.path, ".zig-cache/tmp/{s}", .{self.dir.sub_path});
        self.path[p.len] = 0;
        const params = abi_file_system_std_factory.ke_file_system_std_params{ .root = @ptrCast(&self.path) };
        try R.check(ke_file_system_std_create(&params, &self.handle));
    }

    fn fs(self: *Rig) *abi_file_system.ke_file_system {
        return self.handle.ref.?;
    }

    fn opened(self: *Rig, path: [*:0]const u8) !*abi_file_system.ke_open_file {
        var file: ?*abi_file_system.ke_open_file = null;
        try R.check(self.fs().open.?(self.fs(), path, &file));
        return file.?;
    }

    fn deinit(self: *Rig) void {
        self.handle.destroy.?(self.handle.ref);
        self.dir.cleanup();
    }
};

test "a file under the root opens, reports its size and reads back its bytes" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    const file = try rig.opened("fox.txt");
    defer rig.fs().close.?(rig.fs(), file);

    var len: u64 = 0;
    try R.check(rig.fs().size.?(rig.fs(), file, &len));
    try testing.expectEqual(@as(u64, contents.len), len);

    var buf: [contents.len]u8 = undefined;
    var read: usize = 0;
    try R.check(rig.fs().read_at.?(rig.fs(), file, 0, &buf, buf.len, &read));
    try testing.expectEqualStrings(contents, buf[0..read]);
}

test "a read that crosses the end of the file returns the bytes up to it" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    const file = try rig.opened("fox.txt");
    defer rig.fs().close.?(rig.fs(), file);

    var buf: [16]u8 = undefined;
    var read: usize = 0;
    try R.check(rig.fs().read_at.?(rig.fs(), file, contents.len - 3, &buf, buf.len, &read));
    try testing.expectEqualStrings("dog", buf[0..read]);

    try R.check(rig.fs().read_at.?(rig.fs(), file, contents.len + 10, &buf, buf.len, &read));
    try testing.expectEqual(@as(usize, 0), read);
}

const Reader = struct {
    fs: *abi_file_system.ke_file_system,
    file: *abi_file_system.ke_open_file,
    offset: usize,
    ok: bool = false,

    fn run(self: *Reader) void {
        var buf: [4]u8 = undefined;
        for (0..200) |_| {
            var read: usize = 0;
            if (self.fs.read_at.?(self.fs, self.file, self.offset, &buf, buf.len, &read) != R.ok) return;
            if (!std.mem.eql(u8, buf[0..read], contents[self.offset..][0..buf.len])) return;
        }
        self.ok = true;
    }
};

test "reads of one open file from several threads each get the bytes at their own offset" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    const file = try rig.opened("fox.txt");
    defer rig.fs().close.?(rig.fs(), file);

    var readers: [4]Reader = undefined;
    var threads: [4]std.Thread = undefined;
    for (&readers, &threads, 0..) |*r, *t, i| {
        r.* = .{ .fs = rig.fs(), .file = file, .offset = i * 10 };
        t.* = try std.Thread.spawn(.{}, Reader.run, .{r});
    }
    for (threads) |t| t.join();
    for (readers) |r| try testing.expect(r.ok);
}

test "a path that names nothing is not found by open or stat" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    var file: ?*abi_file_system.ke_open_file = null;
    try testing.expectError(error.NotFound, R.check(rig.fs().open.?(rig.fs(), "missing.txt", &file)));
    try testing.expect(file == null);

    var st: abi_file_system.ke_file_stat = undefined;
    try testing.expectError(error.NotFound, R.check(rig.fs().stat.?(rig.fs(), "missing.txt", &st)));
}

test "stat tells a file and its size from a directory" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    var st: abi_file_system.ke_file_stat = undefined;
    try R.check(rig.fs().stat.?(rig.fs(), "fox.txt", &st));
    try testing.expectEqual(abi_file_system.KE_FILE_KIND_FILE, st.kind);
    try testing.expectEqual(@as(u64, contents.len), st.size);

    try R.check(rig.fs().stat.?(rig.fs(), "sub", &st));
    try testing.expectEqual(abi_file_system.KE_FILE_KIND_DIRECTORY, st.kind);
}

test "an absolute path is read regardless of the root" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    var abs: [std.fs.max_path_bytes]u8 = undefined;
    const real = try rig.dir.dir.realPathFile(testing.io, "fox.txt", &abs);
    abs[real] = 0;

    var cwd_handle: abi_file_system.ke_file_system_handle = undefined;
    try R.check(ke_file_system_std_create(null, &cwd_handle));
    defer cwd_handle.destroy.?(cwd_handle.ref);

    var st: abi_file_system.ke_file_stat = undefined;
    try R.check(cwd_handle.ref.?.stat.?(cwd_handle.ref, @ptrCast(&abs), &st));
    try testing.expectEqual(@as(u64, contents.len), st.size);
}

test "a root that names no directory is not found and leaves the handle zeroed" {
    const params = abi_file_system_std_factory.ke_file_system_std_params{ .root = "no/such/root" };
    var h: abi_file_system.ke_file_system_handle = undefined;
    try testing.expectError(error.NotFound, R.check(ke_file_system_std_create(&params, &h)));
    try testing.expect(h.ref == null and h.destroy == null);
}

test "null arguments are refused as invalid and a null file to close is ignored" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();

    var file: ?*abi_file_system.ke_open_file = null;
    var len: u64 = 0;
    var read: usize = 0;
    var st: abi_file_system.ke_file_stat = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_file_system_std_create(null, null)));
    try testing.expectError(error.InvalidArgument, R.check(open(null, "fox.txt", &file)));
    try testing.expectError(error.InvalidArgument, R.check(open(rig.fs(), null, &file)));
    try testing.expectError(error.InvalidArgument, R.check(size(rig.fs(), null, &len)));
    try testing.expectError(error.InvalidArgument, R.check(readAt(rig.fs(), null, 0, null, 0, &read)));
    try testing.expectError(error.InvalidArgument, R.check(stat(rig.fs(), null, &st)));
    close(rig.fs(), null);
    destroy(null);
}

test "opening, reading, closing and destroying leaves no block allocated" {
    var rig: Rig = undefined;
    try rig.init();
    const file = try rig.opened("fox.txt");
    rig.fs().close.?(rig.fs(), file);
    rig.deinit();
    try heap.expectNoLeaks();
}
