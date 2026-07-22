// The runtime plugin's own heap. Render-phase work is dispatched onto the
// scheduler's pool, so allocation here must be safe from any thread.

const std = @import("std");

const tracking = @import("builtin").mode == .Debug;

var debug_instance: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;

pub const gpa: std.mem.Allocator = if (tracking)
    debug_instance.allocator()
else
    std.heap.smp_allocator;
