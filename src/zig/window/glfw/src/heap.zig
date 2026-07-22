// The glfw window plugin's own heap. Single-instance allocations only (one
// Core, one GlfwDevice per window), so no thread-safety pressure beyond what
// the debug tracker gives for free.

const std = @import("std");

const tracking = @import("builtin").mode == .Debug;

var debug_instance: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;

pub const gpa: std.mem.Allocator = if (tracking)
    debug_instance.allocator()
else
    std.heap.smp_allocator;
