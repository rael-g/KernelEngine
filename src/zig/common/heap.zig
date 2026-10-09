//! The allocator of the engine's native code, chosen at compile time. A Debug build gets `gpa`
//! backed by a thread-safe debug allocator held at file scope, which records every allocation so
//! that `leaks` can count those never freed and `expectNoLeaks` can fail a test on them. Every
//! other build gets the smp allocator itself, tracking nothing, with a leak count that is always
//! zero.

const std = @import("std");

const tracking = @import("builtin").mode == .Debug;

var debug_instance: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;

fn trackedAlloc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    const inner = debug_instance.allocator();
    return inner.vtable.alloc(inner.ptr, len, alignment, ret_addr);
}

fn trackedResize(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    const inner = debug_instance.allocator();
    return inner.vtable.resize(inner.ptr, memory, alignment, new_len, ret_addr);
}

fn trackedRemap(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    const inner = debug_instance.allocator();
    return inner.vtable.remap(inner.ptr, memory, alignment, new_len, ret_addr);
}

fn trackedFree(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    const inner = debug_instance.allocator();
    inner.vtable.free(inner.ptr, memory, alignment, ret_addr);
}

/// Routes each allocator request, and its result, to the allocator inside `debug_instance`. The
/// pointer of the `gpa` value is never read, so a null result of a failed allocation reaches the
/// caller unchanged.
const tracked_vtable: std.mem.Allocator.VTable = .{
    .alloc = trackedAlloc,
    .resize = trackedResize,
    .remap = trackedRemap,
    .free = trackedFree,
};

/// Under Debug it is a value whose vtable forwards to a debug allocator that records what is
/// allocated; in every other mode it is the smp allocator itself.
pub const gpa: std.mem.Allocator = if (tracking)
    .{ .ptr = undefined, .vtable = &tracked_vtable }
else
    std.heap.smp_allocator;

/// Counts the allocations of `gpa` not yet freed, and logs them. Always zero outside Debug.
pub fn leaks() usize {
    if (!tracking) return 0;
    return debug_instance.detectLeaks();
}

/// Fails the running test when `leaks` is not zero.
pub fn expectNoLeaks() !void {
    try std.testing.expectEqual(@as(usize, 0), leaks());
}
