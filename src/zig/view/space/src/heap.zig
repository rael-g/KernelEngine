
const std = @import("std");

/// Debug builds run on the tracking allocator, which catches a double free or
/// a free of the wrong length at the moment it happens instead of leaving a
/// corrupted heap to fail somewhere unrelated. Release uses the lock-free
/// general allocator: the framework is called from runtime systems, which the
/// scheduler may dispatch onto any worker.
const tracking = @import("builtin").mode == .Debug;

var debug_instance: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;

pub const gpa: std.mem.Allocator = if (tracking)
    debug_instance.allocator()
else
    std.heap.smp_allocator;
