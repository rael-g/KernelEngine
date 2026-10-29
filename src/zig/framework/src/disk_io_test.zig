//! A substitute ke_io for the framework's tests that reads the machine's files at once, so a test
//! writes its fixtures to a temporary directory and reads them through the io it gives the object.

const std = @import("std");
const zsub = @import("zsub");
const abi_file_system = @import("abi_file_system");
const abi_io = @import("abi_io");
const abi_result = @import("abi_result");
const heap = @import("heap");

const R = @import("result").Result(.{});

const Io = zsub.For(abi_io.ke_io);

const header = @sizeOf(usize);

const Request = struct {
    outcome: R.Error!abi_io.ke_io_result,
};

fn readWhole(path: [*:0]const u8) R.Error!abi_io.ke_io_result {
    const fp = std.c.fopen(path, "rb") orelse return error.NotFound;
    defer _ = std.c.fclose(fp);
    var list: std.ArrayListUnmanaged(u8) = .empty;
    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = std.c.fread(&chunk, 1, chunk.len, fp);
        if (n == 0) break;
        try list.appendSlice(heap.gpa, chunk[0..n]);
    }
    defer list.deinit(heap.gpa);
    const block = try heap.gpa.alignedAlloc(u8, .of(usize), header + list.items.len);
    std.mem.writeInt(usize, block[0..header], list.items.len, .little);
    @memcpy(block[header..], list.items);
    var result = std.mem.zeroes(abi_io.ke_io_result);
    result.bytes = block[header..].ptr;
    result.size = list.items.len;
    return result;
}

fn statOf(path: [*:0]const u8) R.Error!abi_io.ke_io_result {
    const fp = std.c.fopen(path, "rb") orelse return error.NotFound;
    _ = std.c.fclose(fp);
    var result = std.mem.zeroes(abi_io.ke_io_result);
    result.stat.kind = abi_file_system.KE_FILE_KIND_FILE;
    return result;
}

fn submit(outcome: R.Error!abi_io.ke_io_result) ?*abi_io.ke_io_request {
    const request = heap.gpa.create(Request) catch return null;
    request.* = .{ .outcome = outcome };
    return @ptrCast(request);
}

fn readFile(args: Io.Args(.read_file)) ?*abi_io.ke_io_request {
    return submit(readWhole(args[1].?));
}

fn stat(args: Io.Args(.stat)) ?*abi_io.ke_io_request {
    return submit(statOf(args[1].?));
}

fn wait(args: Io.Args(.wait)) abi_result.ke_result {
    const request: *Request = @ptrCast(@alignCast(args[1] orelse return R.code(error.InvalidArgument)));
    defer heap.gpa.destroy(request);
    if (args[2]) |out| out.* = std.mem.zeroes(abi_io.ke_io_result);
    const result = request.outcome catch |err| return R.code(err);
    if (args[2]) |out| out.* = result;
    return R.ok;
}

fn freeBytes(args: Io.Args(.free_bytes)) void {
    const bytes: [*]align(@alignOf(usize)) u8 = @ptrCast(@alignCast(args[1] orelse return));
    const block = bytes - header;
    const len = std.mem.readInt(usize, block[0..header], .little);
    heap.gpa.free(@as([*]align(@alignOf(usize)) u8, @alignCast(block))[0 .. header + len]);
}

var substitute: Io = undefined;
var configured = false;

pub fn io() ?*abi_io.ke_io {
    if (!configured) {
        substitute.init() catch return null;
        _ = substitute.when(.read_file).does(readFile);
        _ = substitute.when(.stat).does(stat);
        _ = substitute.when(.wait).does(wait);
        _ = substitute.when(.free_bytes).does(freeBytes);
        configured = true;
    }
    return substitute.api();
}
