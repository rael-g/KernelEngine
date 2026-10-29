//! A substitute ke_io for the loader's tests that reads the machine's files at once, so a test
//! writes its fixtures to a temporary directory and reads them through the io it gives the object.

const std = @import("std");
const zsub = @import("zsub");
const abi_io = @import("abi_io");
const abi_result = @import("abi_result");

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
        try list.appendSlice(std.heap.smp_allocator, chunk[0..n]);
    }
    defer list.deinit(std.heap.smp_allocator);
    const block = try std.heap.smp_allocator.alignedAlloc(u8, .of(usize), header + list.items.len);
    std.mem.writeInt(usize, block[0..header], list.items.len, .little);
    @memcpy(block[header..], list.items);
    var result = std.mem.zeroes(abi_io.ke_io_result);
    result.bytes = block[header..].ptr;
    result.size = list.items.len;
    return result;
}

fn existsOf(path: [*:0]const u8) R.Error!abi_io.ke_io_result {
    var result = std.mem.zeroes(abi_io.ke_io_result);
    const fp = std.c.fopen(path, "rb") orelse return result;
    _ = std.c.fclose(fp);
    result.exists = true;
    return result;
}

fn submit(outcome: R.Error!abi_io.ke_io_result, out: *?*abi_io.ke_io_request) abi_result.ke_result {
    const request = std.heap.smp_allocator.create(Request) catch return R.code(error.OutOfMemory);
    request.* = .{ .outcome = outcome };
    out.* = @ptrCast(request);
    return R.ok;
}

fn readFile(args: Io.Args(.read_file)) abi_result.ke_result {
    return submit(readWhole(args[1].?), args[2].?);
}

fn fileExists(args: Io.Args(.file_exists)) abi_result.ke_result {
    return submit(existsOf(args[1].?), args[2].?);
}

fn wait(args: Io.Args(.wait)) abi_result.ke_result {
    const request: *Request = @ptrCast(@alignCast(args[1] orelse return R.code(error.InvalidArgument)));
    defer std.heap.smp_allocator.destroy(request);
    if (args[2]) |out| out.* = std.mem.zeroes(abi_io.ke_io_result);
    const result = request.outcome catch |err| return R.code(err);
    if (args[2]) |out| out.* = result;
    return R.ok;
}

fn freeBytes(args: Io.Args(.free_bytes)) void {
    const bytes: [*]align(@alignOf(usize)) u8 = @ptrCast(@alignCast(args[1] orelse return));
    const block = bytes - header;
    const len = std.mem.readInt(usize, block[0..header], .little);
    std.heap.smp_allocator.free(@as([*]align(@alignOf(usize)) u8, @alignCast(block))[0 .. header + len]);
}

var substitute: Io = undefined;
var configured = false;

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
