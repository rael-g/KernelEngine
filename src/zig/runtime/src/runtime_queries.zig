//! Resolves a system's queries into the segments its body reads, in buffers that grow until the
//! world's answer fits.

const std = @import("std");

const abi_ecs = @import("abi_ecs");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const heap = @import("heap");
const R = @import("result").Result(.{});
const alloc = @import("runtime_alloc.zig");
const cAlloc = alloc.cAlloc;
const cFree = alloc.cFree;
const cAllocBytes = alloc.cAllocBytes;
const cFreeBytes = alloc.cFreeBytes;


pub const initial_segments_per_query = 4;
pub const resolve_attempts = 3;
/// A query of a registered system. Its `terms` point into the system's own term storage, not into
/// the array the caller passed.
pub const QueryDecl = struct {
    terms: [*]const abi_runtime.ke_component_access,
    term_count: u32,
};

/// The render copy of one query: the matched entities and one column buffer per term, all sized to
/// `capacity`. The buffers are kept across ticks and grown by `runtimeExtractRenderState`, which
/// points `seg` at them.
pub const ExtractedQuery = struct {
    seg: abi_ecs.ke_ecs_segment,
    entities_buf: ?[*]abi_ecs.ke_entity,
    col_bufs: []?*anyopaque,
    col_elem_size: []usize,
    col_ptrs: []?*anyopaque,
    capacity: usize,
    elem_sizes_cached: bool,
};

/// Storage for the segments one query resolves into, with one column pointer per term for each
/// segment. A `RegisteredSystem` owns one per query.
pub const SegBuf = struct {
    ptr: ?[*]abi_ecs.ke_ecs_segment = null,
    cap: usize = 0,
    cols: ?[*]?*anyopaque = null,
    cols_cap: usize = 0,

    pub fn free(self: *SegBuf) void {
        cFree(abi_ecs.ke_ecs_segment, self.ptr, self.cap);
        cFree(?*anyopaque, self.cols, self.cols_cap);
        self.* = .{};
    }

    /// Replaces both arrays when either is too small for the requested number of segments and
    /// columns. The old contents are not carried over.
    pub fn reserve(self: *SegBuf, needed: usize, terms: usize) bool {
        if (needed <= self.cap and needed * terms <= self.cols_cap) return true;
        const segments = cAlloc(abi_ecs.ke_ecs_segment, needed) orelse return false;
        const columns = cAlloc(?*anyopaque, needed * terms) orelse {
            cFree(abi_ecs.ke_ecs_segment, segments, needed);
            return false;
        };
        cFree(abi_ecs.ke_ecs_segment, self.ptr, self.cap);
        cFree(?*anyopaque, self.cols, self.cols_cap);
        self.* = .{ .ptr = segments, .cap = needed, .cols = columns, .cols_cap = needed * terms };
        return true;
    }
};

/// Resolves a query into the buffer, growing it to the match count the ecs reports and asking
/// again. Returns the number of matched segments; out of memory when the buffer cannot grow or the
/// count does not settle within the attempts allowed, and the ecs's own failure when it refuses.
pub fn resolveInto(ecs: *abi_ecs.ke_ecs, query: abi_ecs.ke_query_id, buf: *SegBuf, terms: usize) R.Error!usize {
    if (!buf.reserve(initial_segments_per_query, terms)) return error.OutOfMemory;
    for (0..resolve_attempts) |_| {
        var matched: usize = 0;
        try R.check(ecs.query_resolve.?(ecs, query, buf.ptr, buf.cap, &buf.cols.?[0], &matched));
        if (matched <= buf.cap) return matched;
        if (!buf.reserve(matched, terms)) return error.OutOfMemory;
    }
    return error.OutOfMemory;
}
