//! The runtime's allocations of C-shaped arrays and byte blocks, freed by the length they were made with.

const heap = @import("heap");

pub fn cAlloc(comptime T: type, n: usize) ?[*]T {
    if (n == 0) return null;
    const slice = heap.gpa.alloc(T, n) catch return null;
    return slice.ptr;
}

/// Frees a block that `cAlloc` returned. The count must be the one it was allocated with, because
/// the allocator frees by length.
pub fn cFree(comptime T: type, p: ?[*]T, n: usize) void {
    if (p) |pp| heap.gpa.free(pp[0..n]);
}

pub fn cAllocBytes(n: usize) ?*anyopaque {
    if (n == 0) return null;
    const slice = heap.gpa.alloc(u8, n) catch return null;
    return slice.ptr;
}

pub fn cFreeBytes(p: ?*anyopaque, n: usize) void {
    if (p) |pp| heap.gpa.free(@as([*]u8, @ptrCast(pp))[0..n]);
}
