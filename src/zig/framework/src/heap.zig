// The framework plugin's own heap.
//
// One allocator for the whole plugin rather than one per factory: several
// entry points here (the primitive baker) are reached from C without a self
// pointer to hang state on, and a buffer baked through one path is released
// through another. A single heap makes that pairing correct by construction.
//
// Memory that comes from a C library is NOT this heap's: tomlc99 hands back
// strings it allocated with malloc, and those keep going back to free().

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
