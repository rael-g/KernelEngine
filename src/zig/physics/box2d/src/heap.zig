// The box2d plugin's own heap. Only the body table lives here — Box2D itself
// manages its own internal memory behind the C API.

const std = @import("std");

const tracking = @import("builtin").mode == .Debug;

var debug_instance: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;

pub const gpa: std.mem.Allocator = if (tracking)
    debug_instance.allocator()
else
    std.heap.smp_allocator;
