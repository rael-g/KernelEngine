//! Reads whole files through the ke_io a framework object was given.

const std = @import("std");
const abi_io = @import("abi_io");
const heap = @import("heap");

const R = @import("result").Result(.{});

/// The whole file at `path` with a terminating zero, owned by the caller and freed with the heap's
/// allocator. Fails with the read's error: not found when there is no such file.
pub fn readText(io: *abi_io.c.ke_io, path: [*:0]const u8) R.Error![:0]u8 {
    var request: ?*abi_io.c.ke_io_request = null;
    try R.check(io.read_file.?(io, path, &request));
    var result: abi_io.c.ke_io_result = undefined;
    try R.check(io.wait.?(io, request, &result));
    defer io.free_bytes.?(io, result.bytes);
    const bytes: []const u8 = if (result.bytes) |b| @as([*]const u8, @ptrCast(b))[0..@intCast(result.size)] else "";
    return heap.gpa.dupeZ(u8, bytes);
}
