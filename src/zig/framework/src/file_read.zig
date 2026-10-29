//! Reads whole files and asks whether a path names a file, through the ke_io a framework object
//! was given.

const std = @import("std");
const abi_io = @import("abi_io");
const heap = @import("heap");

const R = @import("result").Result(.{});

/// The whole file at `path` with a terminating zero, owned by the caller and freed with the heap's
/// allocator. Fails with the read's error: not found when there is no such file.
pub fn readText(io: *abi_io.ke_io, path: [*:0]const u8) R.Error![:0]u8 {
    var request: ?*abi_io.ke_io_request = null;
    try R.check(io.read_file.?(io, path, &request));
    var result: abi_io.ke_io_result = undefined;
    try R.check(io.wait.?(io, request, &result));
    defer io.free_bytes.?(io, result.bytes);
    const bytes: []const u8 = if (result.bytes) |b| @as([*]const u8, @ptrCast(b))[0..@intCast(result.size)] else "";
    return heap.gpa.dupeZ(u8, bytes);
}

/// Whether `path` names a regular file; any failure to ask reads as no.
pub fn isFile(io: *abi_io.ke_io, path: [*:0]const u8) bool {
    var request: ?*abi_io.ke_io_request = null;
    if (io.file_exists.?(io, path, &request) != R.ok) return false;
    var result: abi_io.ke_io_result = undefined;
    if (io.wait.?(io, request, &result) != R.ok) return false;
    return result.exists;
}
