// The enki scheduler plugin's own heap.
//
// A Task is allocated by whichever thread calls dispatch/dispatch_pinned and
// freed by whichever thread later calls wait — both can be any worker the
// caller picks, so the allocator backing this must be thread-safe.

const std = @import("std");

const tracking = @import("builtin").mode == .Debug;

var debug_instance: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;

pub const gpa: std.mem.Allocator = if (tracking)
    debug_instance.allocator()
else
    std.heap.smp_allocator;
