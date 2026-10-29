//! A substitute ke_io for the framework's tests that serves the files a test puts into it from
//! memory, so no test reads the machine's files.

const std = @import("std");
const zsub = @import("zsub");
const abi_io = @import("abi_io");
const abi_result = @import("abi_result");

const R = @import("result").Result(.{});

const Io = zsub.For(abi_io.ke_io);

const table_heap = std.heap.smp_allocator;

const Request = struct {
    outcome: R.Error!abi_io.ke_io_result,
};

var files: std.StringHashMapUnmanaged([]const u8) = .empty;
var substitute: Io = undefined;
var configured = false;

fn keyOf(buf: []u8, path: []const u8) ![]const u8 {
    var fba = std.heap.FixedBufferAllocator.init(buf);
    return std.fs.path.resolvePosix(fba.allocator(), &.{path});
}

/// Serves `contents` for `path` until `remove` is called with the same path; both are copied.
pub fn put(path: []const u8, contents: []const u8) !void {
    var buf: [std.fs.max_path_bytes * 2]u8 = undefined;
    const key = try keyOf(&buf, path);
    remove(path);
    const owned_key = try table_heap.dupe(u8, key);
    errdefer table_heap.free(owned_key);
    const owned = try table_heap.dupe(u8, contents);
    errdefer table_heap.free(owned);
    try files.put(table_heap, owned_key, owned);
}

/// Stops serving `path`.
pub fn remove(path: []const u8) void {
    var buf: [std.fs.max_path_bytes * 2]u8 = undefined;
    const key = keyOf(&buf, path) catch return;
    if (files.fetchRemove(key)) |entry| {
        table_heap.free(entry.key);
        table_heap.free(entry.value);
    }
}

fn find(path: [*:0]const u8) ?[]const u8 {
    var buf: [std.fs.max_path_bytes * 2]u8 = undefined;
    const key = keyOf(&buf, std.mem.span(path)) catch return null;
    return files.get(key);
}

fn submit(outcome: R.Error!abi_io.ke_io_result, out: *?*abi_io.ke_io_request) abi_result.ke_result {
    const request = table_heap.create(Request) catch return R.code(error.OutOfMemory);
    request.* = .{ .outcome = outcome };
    out.* = @ptrCast(request);
    return R.ok;
}

fn readFile(args: Io.Args(.read_file)) abi_result.ke_result {
    var result = std.mem.zeroes(abi_io.ke_io_result);
    const outcome: R.Error!abi_io.ke_io_result = if (find(args[1].?)) |bytes| blk: {
        result.bytes = @constCast(bytes.ptr);
        result.size = bytes.len;
        break :blk result;
    } else error.NotFound;
    return submit(outcome, args[2].?);
}

fn fileExists(args: Io.Args(.file_exists)) abi_result.ke_result {
    var result = std.mem.zeroes(abi_io.ke_io_result);
    result.exists = find(args[1].?) != null;
    return submit(result, args[2].?);
}

fn wait(args: Io.Args(.wait)) abi_result.ke_result {
    const request: *Request = @ptrCast(@alignCast(args[1] orelse return R.code(error.InvalidArgument)));
    defer table_heap.destroy(request);
    if (args[2]) |out| out.* = std.mem.zeroes(abi_io.ke_io_result);
    const result = request.outcome catch |err| return R.code(err);
    if (args[2]) |out| out.* = result;
    return R.ok;
}

fn freeBytes(_: Io.Args(.free_bytes)) void {}

pub fn io() ?*abi_io.ke_io {
    if (!configured) {
        substitute.init() catch return null;
        _ = substitute.when(.read_file).does(readFile);
        _ = substitute.when(.file_exists).does(fileExists);
        _ = substitute.when(.wait).does(wait);
        _ = substitute.when(.free_bytes).does(freeBytes);
        configured = true;
    }
    return substitute.api();
}

var next_dir: u32 = 0;

/// A directory of its own in the served table, so tests never share a path.
pub const Dir = struct {
    buf: [32]u8,
    len: usize,

    pub fn init() Dir {
        var self = Dir{ .buf = undefined, .len = 0 };
        next_dir += 1;
        self.len = if (std.fmt.bufPrint(&self.buf, "fixtures/{d}", .{next_dir})) |name| name.len else |_| 0;
        return self;
    }

    pub fn path(self: *const Dir) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn writeFile(self: *const Dir, name: []const u8, contents: []const u8) !void {
        var full: [std.fs.max_path_bytes]u8 = undefined;
        try put(try std.fmt.bufPrint(&full, "{s}/{s}", .{ self.path(), name }), contents);
    }

    pub fn cleanup(self: *const Dir) void {
        var it = files.iterator();
        while (it.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, self.path()) and entry.key_ptr.*.len > self.len and entry.key_ptr.*[self.len] == '/') {
                const key = entry.key_ptr.*;
                const value = entry.value_ptr.*;
                files.removeByPtr(entry.key_ptr);
                table_heap.free(key);
                table_heap.free(value);
                it = files.iterator();
            }
        }
    }
};
