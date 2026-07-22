// The flecs plugin's own heap. Backs the query cache arrays only — flecs
// itself manages its archetype storage behind its own os_api allocator hooks
// (left at their defaults; only log_ and abort_ are overridden).

const std = @import("std");

const tracking = @import("builtin").mode == .Debug;

var debug_instance: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;

pub const gpa: std.mem.Allocator = if (tracking)
    debug_instance.allocator()
else
    std.heap.smp_allocator;
