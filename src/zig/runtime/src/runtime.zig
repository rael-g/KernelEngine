//! The `ke_runtime` plugin: it registers systems and modules and runs the phase loop of a tick
//! over an ecs and a scheduler it borrows. It holds no component data.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_runtime").logFn };

const abi_ecs = @import("abi_ecs");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const abi_runtime_factory = @import("abi_runtime_factory");
const abi_scheduler = @import("abi_scheduler");
const alloc = @import("runtime_alloc.zig");
const wave_mod = @import("runtime_waves.zig");
const context = @import("runtime_context.zig");
const queries_mod = @import("runtime_queries.zig");
const cAlloc = alloc.cAlloc;
const cFree = alloc.cFree;
const cAllocBytes = alloc.cAllocBytes;
const cFreeBytes = alloc.cFreeBytes;

const DeferKind = context.DeferKind;
const DeferCommand = context.DeferCommand;
const DeferQueue = context.DeferQueue;
const CtxState = context.CtxState;
const ctxOf = context.ctxOf;
const commandsOf = context.commandsOf;
const bindCtx = context.bindCtx;
const ctxView = context.ctxView;
const deferReserve = context.deferReserve;
const defer_arena_align = context.defer_arena_align;
const deferArenaPush = context.deferArenaPush;
const ctxSlice = context.ctxSlice;
const recordTarget = context.recordTarget;
const recordCommand = context.recordCommand;
const commandsSpawn = context.commandsSpawn;
const commandsAttach = context.commandsAttach;
const commandsDetach = context.commandsDetach;
const commandsDespawn = context.commandsDespawn;
const commandsDefer = context.commandsDefer;
const s_defer_applied_total = context.s_defer_applied_total;
const deferFlush = context.deferFlush;
const deferAppliedCount = context.deferAppliedCount;
const resetDeferApplied = context.resetDeferApplied;
const initial_segments_per_query = queries_mod.initial_segments_per_query;
const resolve_attempts = queries_mod.resolve_attempts;
const QueryDecl = queries_mod.QueryDecl;
const ExtractedQuery = queries_mod.ExtractedQuery;
const SegBuf = queries_mod.SegBuf;
const resolveInto = queries_mod.resolveInto;

const R = @import("result").Result(.{});
const log = std.log.scoped(.runtime);

/// Logs why a call fails and returns `err` for it to fail with.
fn reportFailure(err: R.Error, comptime why: []const u8) R.Error {
    log.warn(why, .{});
    return err;
}


const KE_RUNTIME_PHASE_COUNT = 9;

const ACCESS_WRITE: c_uint = @intCast(abi_runtime.KE_ACCESS_WRITE);

const heap = @import("heap");

/// A system as the runtime holds it: its own copy of the declaration, the storage of its queries,
/// and the access list that the conflict rule reads. It is linked through `pending_next` while it
/// waits in `RuntimeState.pending_systems`, and `releaseSystem` frees all of it.
const RegisteredSystem = struct {
    id: u64,
    pending_next: ?*RegisteredSystem,
    params: abi_runtime.ke_runtime_system_params,
    query_decls: []QueryDecl,
    query_ids: []abi_ecs.ke_query_id,
    query_count: u32,
    segs: []SegBuf,
    seg_ptrs: []?[*]const abi_ecs.ke_ecs_segment,
    seg_counts: []usize,
    extracted: []ExtractedQuery,
    derived_access: []abi_runtime.ke_component_access,
    term_storage: []abi_runtime.ke_component_access,
    derived_access_count: u32,
    name_storage: ?[]u8,
    access_storage: ?[]abi_runtime.ke_component_access,
    explicit_access: []abi_runtime.ke_component_access,
    order_names: [][:0]u8,
    order_ptrs: [][*c]const u8,
};

fn freeSlice(comptime T: type, slice: []T) void {
    if (slice.len != 0) heap.gpa.free(slice);
}

fn allocZeroed(comptime T: type, n: usize) ?[]T {
    const slice = heap.gpa.alloc(T, n) catch return null;
    @memset(std.mem.sliceAsBytes(slice), 0);
    return slice;
}

/// Allocates every array a registered system needs for its queries in one pass, so `buildSystem`
/// only fills them. On failure it returns false with the arrays allocated so far still attached to
/// the system, for `releaseSystem` to free.
fn allocQueryStorage(rs: *RegisteredSystem, queries: [*c]const abi_runtime.ke_query_decl, query_count: usize, total_terms: usize, access_count: usize) bool {
    rs.term_storage = allocZeroed(abi_runtime.ke_component_access, total_terms) orelse return false;
    rs.query_decls = allocZeroed(QueryDecl, query_count) orelse return false;
    rs.query_ids = allocZeroed(abi_ecs.ke_query_id, query_count) orelse return false;
    rs.segs = allocZeroed(SegBuf, query_count) orelse return false;
    rs.seg_ptrs = allocZeroed(?[*]const abi_ecs.ke_ecs_segment, query_count) orelse return false;
    rs.seg_counts = allocZeroed(usize, query_count) orelse return false;
    rs.extracted = allocZeroed(ExtractedQuery, query_count) orelse return false;
    rs.derived_access = allocZeroed(abi_runtime.ke_component_access, total_terms + access_count) orelse return false;
    for (rs.extracted, 0..) |*eq, q| {
        const terms = queries[q].term_count;
        eq.col_bufs = allocZeroed(?*anyopaque, terms) orelse return false;
        eq.col_elem_size = allocZeroed(usize, terms) orelse return false;
        eq.col_ptrs = allocZeroed(?*anyopaque, terms) orelse return false;
    }
    return true;
}

/// Frees everything a registered system owns, its own record included. It runs when a system is
/// removed, when its registration fails, and when a system is still pending at teardown.
fn releaseSystem(rs: *RegisteredSystem) void {
    for (rs.extracted) |*eq| {
        if (eq.entities_buf) |eb| cFree(abi_ecs.ke_entity, eb, eq.capacity);
        for (eq.col_bufs, 0..) |col, t| {
            if (col) |cb| cFreeBytes(cb, eq.col_elem_size[t] *% eq.capacity);
        }
        freeSlice(?*anyopaque, eq.col_bufs);
        freeSlice(usize, eq.col_elem_size);
        freeSlice(?*anyopaque, eq.col_ptrs);
    }
    freeSlice(abi_runtime.ke_component_access, rs.term_storage);
    if (rs.name_storage) |n| heap.gpa.free(n);
    if (rs.access_storage) |a| heap.gpa.free(a);
    freeSlice(abi_runtime.ke_component_access, rs.explicit_access);
    for (rs.order_names) |n| heap.gpa.free(n);
    freeSlice([:0]u8, rs.order_names);
    freeSlice([*c]const u8, rs.order_ptrs);
    for (rs.segs) |*buf| buf.free();
    freeSlice(QueryDecl, rs.query_decls);
    freeSlice(abi_ecs.ke_query_id, rs.query_ids);
    freeSlice(SegBuf, rs.segs);
    freeSlice(?[*]const abi_ecs.ke_ecs_segment, rs.seg_ptrs);
    freeSlice(usize, rs.seg_counts);
    freeSlice(ExtractedQuery, rs.extracted);
    freeSlice(abi_runtime.ke_component_access, rs.derived_access);
    cFree(RegisteredSystem, @ptrCast(rs), 1);
}

/// What the runtime keeps of a module: the data and the unload hook it registered with. A module
/// whose load hook refused has both cleared.
const RegisteredModule = struct {
    user_data: ?*anyopaque,
    on_unload: abi_runtime.ke_module_unload_fn,
};

/// The render phase of one tick. The render phase overlaps the sim: its bodies read only the
/// copies `runtimeExtractRenderState` made, so the next tick may write the ecs while the previous
/// frame is drawn, and that tick joins the job before it overwrites the copies. One job is
/// allocated and reused for every tick; `runtimeTickBody` sets `h` and `dt` before dispatch, and
/// `runtimeJoinPendingRender` reads `failure` back once the task has been waited for.
const RenderJob = struct {
    h: *RuntimeHandle,
    dt: f32,
    failure: PhaseFailure = .{},
};

/// A removal requested while a tick or the render phase was in flight, linked on
/// `RuntimeState.pending_removals` until the next tick applies it.
const PendingRemoval = struct {
    id: abi_runtime.ke_system_id,
    next: ?*PendingRemoval,
};

/// The state every function of the file works on. The system list is edited only while nothing
/// runs: `in_tick` and `in_render` decide whether a registration or removal waits on the lock-free
/// `pending_systems` and `pending_removals` lists, which the next tick drains in call order.
/// Each registered system is a private copy of what the caller declared, so the caller's arrays
/// need not outlive the call. `systems_prepared` counts the systems at the front of
/// the array whose queries are bound. The per-phase scratch arrays hold one block of
/// `max_systems_per_phase` entries per phase, and `pending_render_task` with `render_job` describe
/// the render phase in flight, if any.
const RuntimeState = struct {
    ecs: *abi_ecs.ke_ecs,
    scheduler: *abi_scheduler.ke_scheduler,
    systems: ?[*]?*RegisteredSystem,
    system_count: usize,
    system_capacity: usize,
    modules: ?[*]RegisteredModule,
    module_count: usize,
    module_capacity: usize,
    next_module_id: u64,
    next_system_id: u64,
    fixed_dt: f32,
    fixed_dt_max_accum: f32,
    fixed_accumulator: f32,
    started: bool,
    in_tick: std.atomic.Value(bool),
    in_render: std.atomic.Value(bool),
    pending_systems: std.atomic.Value(?*RegisteredSystem),
    pending_removals: std.atomic.Value(?*PendingRemoval),
    max_systems_per_phase: u32,
    extract_scratch: SegBuf,
    phase_indices: ?[*]u32,
    phase_params: ?[*]abi_runtime.ke_runtime_system_params,
    wave_assignments: ?[*]u32,
    phase_pkgs: ?[*]TaskPkg,
    phase_tasks: ?[*]?*abi_scheduler.ke_task,
    systems_prepared: usize,
    pending_render_task: ?*abi_scheduler.ke_task,
    render_job: ?*RenderJob,
    exclusive: std.ArrayList(wave_mod.Exclusive),
    self_ordered: std.ArrayList(abi_ecs.ke_component_id),

    fn rules(self: *const RuntimeState) wave_mod.Rules {
        return .{ .exclusive = self.exclusive.items, .self_ordered = self.self_ordered.items };
    }
};

/// What the `ke_runtime` handle points to. `ke_runtime_create` fills the `api` table with this
/// file's functions and points the table's handle field back here, so every entry reaches the state
/// through `handleOf`. It is allocated by `ke_runtime_create` and freed by `runtimeDestroy`.
const RuntimeHandle = struct {
    api: abi_runtime.ke_runtime,
    state: RuntimeState,
};

fn handleOf(self: *abi_runtime.ke_runtime) *RuntimeHandle {
    return @ptrCast(@alignCast(self.handle));
}

/// Slot `register_module`. Writes the module's id, or zero on failure. Fails with invalid argument
/// for a null runtime, out-parameter or load hook, with out of memory when the module array cannot
/// grow, and with the hook's own code when it fails. The hook runs with the module already
/// recorded, so systems it registers are registered before the call returns; a refused module has
/// its unload hook cleared and is never unloaded.
fn runtimeRegisterModule(self: ?*abi_runtime.ke_runtime, p: [*c]const abi_runtime.ke_runtime_module_params, out_id: ?*abi_runtime.ke_module_id) callconv(.c) abi_result.ke_result {
    const out = out_id orelse return R.code(error.InvalidArgument);
    out.* = 0;
    if (self == null or self.?.handle == null or p == null or p.*.on_load == null) {
        return R.code(reportFailure(error.InvalidArgument, "invalid argument"));
    }
    const h = handleOf(self.?);

    if (h.state.module_count == h.state.module_capacity) {
        const new_cap: usize = if (h.state.module_capacity != 0) h.state.module_capacity * 2 else 4;
        const new_buf = cAlloc(RegisteredModule, new_cap) orelse {
            return R.code(reportFailure(error.OutOfMemory, "module array allocation failed"));
        };
        if (h.state.modules) |old| {
            @memcpy(new_buf[0..h.state.module_count], old[0..h.state.module_count]);
            cFree(RegisteredModule, old, h.state.module_capacity);
        }
        h.state.modules = new_buf;
        h.state.module_capacity = new_cap;
    }

    const slot = h.state.module_count;
    h.state.modules.?[slot] = .{ .user_data = p.*.user_data, .on_unload = p.*.on_unload };
    h.state.module_count += 1;

    h.state.next_module_id += 1;
    const id = h.state.next_module_id;
    const loaded = p.*.on_load.?(self, p.*.user_data);
    if (loaded != R.ok) {
        h.state.modules.?[slot] = .{ .user_data = null, .on_unload = null };
        log.warn("module {s} refused to load", .{spanOr(p.*.name)});
        return loaded;
    }
    out.* = id;
    return R.ok;
}

/// Adds a component access to `derived_access`, or-ing the access bits into the entry the same
/// component already has, so each component appears once.
fn mergeAccess(rs: *RegisteredSystem, want: abi_runtime.ke_component_access) void {
    for (0..rs.derived_access_count) |d| {
        if (rs.derived_access[d].cid == want.cid) {
            rs.derived_access[d].access |= want.access;
            return;
        }
    }
    rs.derived_access[rs.derived_access_count] = want;
    rs.derived_access_count += 1;
}

/// Copies a registration into a new `RegisteredSystem` that owns its name, its query terms and its
/// access list. When the declaration has queries, their terms are merged with its access list into
/// `derived_access`, and the copy's `params` drops the queries, so from then on the access list
/// alone describes the system. On failure nothing stays allocated.
fn buildSystem(p: [*c]const abi_runtime.ke_runtime_system_params) R.Error!*RegisteredSystem {
    var total_terms: usize = 0;
    if (p.*.query_count > 0) {
        if (p.*.queries == null) {
            return reportFailure(error.InvalidArgument, "queries are counted but not given");
        }
        for (0..p.*.query_count) |q| {
            const decl = p.*.queries.?[q];
            if (decl.term_count == 0 or decl.terms == null) {
                return reportFailure(error.InvalidArgument, "a query declares no terms");
            }
            total_terms += decl.term_count;
        }
    }

    const rs_mem = cAlloc(RegisteredSystem, 1) orelse {
        return reportFailure(error.OutOfMemory, "registered_system allocation failed");
    };
    const rs = &rs_mem[0];
    rs.params = p.*;
    rs.id = 0;
    rs.pending_next = null;
    rs.query_count = 0;
    rs.query_decls = &.{};
    rs.query_ids = &.{};
    rs.segs = &.{};
    rs.seg_ptrs = &.{};
    rs.seg_counts = &.{};
    rs.extracted = &.{};
    rs.derived_access = &.{};
    rs.term_storage = &.{};
    rs.derived_access_count = 0;
    rs.name_storage = null;
    rs.access_storage = null;
    rs.explicit_access = &.{};
    rs.order_names = &.{};
    rs.order_ptrs = &.{};

    if (!copyOrderNames(rs, p)) {
        releaseSystem(rs);
        return reportFailure(error.OutOfMemory, "system order names allocation failed");
    }
    if (p.*.access_count > 0 and p.*.access_list != null) {
        rs.explicit_access = heap.gpa.dupe(abi_runtime.ke_component_access, p.*.access_list.?[0..p.*.access_count]) catch {
            releaseSystem(rs);
            return reportFailure(error.OutOfMemory, "system access list allocation failed");
        };
    }

    if (p.*.name != null) {
        const text = std.mem.span(p.*.name.?);
        const copy = heap.gpa.alloc(u8, text.len + 1) catch {
            releaseSystem(rs);
            return reportFailure(error.OutOfMemory, "system name allocation failed");
        };
        @memcpy(copy[0..text.len], text);
        copy[text.len] = 0;
        rs.name_storage = copy;
        rs.params.name = @ptrCast(copy.ptr);
    }

    if (p.*.query_count > 0) {
        const qn = p.*.query_count;
        if (!allocQueryStorage(rs, p.*.queries, qn, total_terms, p.*.access_count)) {
            releaseSystem(rs);
            return reportFailure(error.OutOfMemory, "query storage allocation failed");
        }

        var term_at: usize = 0;
        for (0..qn) |q| {
            const decl = p.*.queries.?[q];
            const owned = rs.term_storage[term_at..][0..decl.term_count];
            @memcpy(owned, decl.terms.?[0..decl.term_count]);
            term_at += decl.term_count;
            rs.query_decls[q] = .{ .terms = owned.ptr, .term_count = decl.term_count };
            rs.query_ids[q] = abi_ecs.KE_QUERY_INVALID;
            for (owned) |term| mergeAccess(rs, term);
        }
        rs.query_count = qn;

        for (0..p.*.access_count) |i| mergeAccess(rs, p.*.access_list.?[i]);

        rs.params.access_list = rs.derived_access.ptr;
        rs.params.access_count = rs.derived_access_count;
        rs.params.queries = null;
        rs.params.query_count = 0;

        for (0..qn) |q| {
            if (!rs.segs[q].reserve(initial_segments_per_query, rs.query_decls[q].term_count)) {
                releaseSystem(rs);
                return reportFailure(error.OutOfMemory, "query segment storage allocation failed");
            }
            rs.seg_ptrs[q] = rs.segs[q].ptr;
        }
    } else if (p.*.access_list != null and p.*.access_count > 0) {
        const copy = heap.gpa.alloc(abi_runtime.ke_component_access, p.*.access_count) catch {
            releaseSystem(rs);
            return reportFailure(error.OutOfMemory, "system access list allocation failed");
        };
        @memcpy(copy, p.*.access_list.?[0..p.*.access_count]);
        rs.access_storage = copy;
        rs.params.access_list = copy.ptr;
    }

    return rs;
}

/// Copies the names of `after` and `before` into the system, whose `params` then point at the
/// copies: `after` first in `order_ptrs`, `before` after it. False when an allocation fails, with
/// what was copied left for `releaseSystem`.
fn copyOrderNames(rs: *RegisteredSystem, p: [*c]const abi_runtime.ke_runtime_system_params) bool {
    const after: usize = if (p.*.after != null) p.*.after_count else 0;
    const before: usize = if (p.*.before != null) p.*.before_count else 0;
    rs.params.after = null;
    rs.params.after_count = 0;
    rs.params.before = null;
    rs.params.before_count = 0;
    if (after + before == 0) return true;
    rs.order_ptrs = allocZeroed([*c]const u8, after + before) orelse return false;
    rs.order_names = allocZeroed([:0]u8, after + before) orelse return false;
    var made: usize = 0;
    for (0..after + before) |k| {
        const src = if (k < after) p.*.after.?[k] else p.*.before.?[k - after];
        const copy = heap.gpa.dupeZ(u8, if (src != null) std.mem.span(src.?) else "") catch {
            rs.order_names = rs.order_names[0..made];
            return false;
        };
        rs.order_names[k] = copy;
        rs.order_ptrs[k] = copy.ptr;
        made += 1;
    }
    rs.params.after = rs.order_ptrs.ptr;
    rs.params.after_count = @intCast(after);
    rs.params.before = rs.order_ptrs.ptr + after;
    rs.params.before_count = @intCast(before);
    return true;
}

/// Appends a system to the list in registration order. It refuses a system whose phase already
/// holds the maximum number of systems. A refused system is not added and stays owned by the
/// caller.
fn appendSystem(h: *RuntimeHandle, rs: *RegisteredSystem) R.Error!void {
    var in_phase: u32 = 0;
    for (0..h.state.system_count) |si| {
        if (h.state.systems.?[si].?.params.phase == rs.params.phase) in_phase += 1;
    }
    if (in_phase >= h.state.max_systems_per_phase) {
        return reportFailure(error.OutOfMemory, "phase is at its max_systems_per_phase limit");
    }

    if (h.state.system_count == h.state.system_capacity) {
        const new_cap: usize = if (h.state.system_capacity != 0) h.state.system_capacity * 2 else 4;
        const new_buf = cAlloc(?*RegisteredSystem, new_cap) orelse {
            return reportFailure(error.OutOfMemory, "system array allocation failed");
        };
        if (h.state.systems) |old| {
            @memcpy(new_buf[0..h.state.system_count], old[0..h.state.system_count]);
            cFree(?*RegisteredSystem, old, h.state.system_capacity);
        }
        h.state.systems = new_buf;
        h.state.system_capacity = new_cap;
    }

    h.state.systems.?[h.state.system_count] = rs;
    h.state.system_count += 1;
}

/// Slot `register_system`. Returns the id at once, whether or not the system is yet in the list.
/// While a tick or a render phase is in flight the system is pushed onto
/// `RuntimeState.pending_systems` with a compare-exchange; otherwise the render phase in flight is
/// joined and the system is appended now.
fn runtimeRegisterSystem(self: ?*abi_runtime.ke_runtime, p: [*c]const abi_runtime.ke_runtime_system_params, out_id: ?*abi_runtime.ke_system_id) callconv(.c) abi_result.ke_result {
    const out = out_id orelse return R.code(error.InvalidArgument);
    out.* = 0;
    if (self == null or self.?.handle == null or p == null or p.*.execute == null) {
        return R.code(reportFailure(error.InvalidArgument, "invalid argument"));
    }
    const h = handleOf(self.?);

    const rs = buildSystem(p) catch |err| return R.code(err);
    rs.id = @atomicRmw(u64, &h.state.next_system_id, .Add, 1, .monotonic) + 1;
    if (h.state.in_tick.load(.acquire) or h.state.in_render.load(.acquire)) {
        var head = h.state.pending_systems.load(.acquire);
        while (true) {
            rs.pending_next = head;
            head = h.state.pending_systems.cmpxchgWeak(head, rs, .release, .acquire) orelse {
                out.* = rs.id;
                return R.ok;
            };
        }
    }
    _ = runtimeJoinPendingRender(h);
    appendSystem(h, rs) catch |err| {
        releaseSystem(rs);
        return R.code(err);
    };
    out.* = rs.id;
    return R.ok;
}

/// Called at the start of `runtimeTick`, before `in_tick` is raised. When anything is pending it
/// first joins the render phase in flight, then appends the pending systems in call order and
/// applies the pending removals in call order, so a removal queued for a system registered in the
/// same window still finds it.
fn applyPendingSystems(h: *RuntimeHandle) void {
    var stack = h.state.pending_systems.swap(null, .acq_rel);
    var removals = h.state.pending_removals.swap(null, .acq_rel);
    if (stack == null and removals == null) return;
    _ = runtimeJoinPendingRender(h);
    var reversed: ?*RegisteredSystem = null;
    while (stack) |rs| {
        stack = rs.pending_next;
        rs.pending_next = reversed;
        reversed = rs;
    }
    while (reversed) |rs| {
        reversed = rs.pending_next;
        rs.pending_next = null;
        appendSystem(h, rs) catch releaseSystem(rs);
    }

    var reversed_removals: ?*PendingRemoval = null;
    while (removals) |r| {
        removals = r.next;
        r.next = reversed_removals;
        reversed_removals = r;
    }
    while (reversed_removals) |r| {
        reversed_removals = r.next;
        _ = removeSystemNow(h, r.id);
        cFree(PendingRemoval, @ptrCast(r), 1);
    }
}

/// Removes the system with the given id from the list, shifting the later ones down and keeping
/// `systems_prepared` in step, then releases it. Returns false when no system has that id. Both
/// callers have joined the render phase first, since the removed system may be one a render job
/// reads.
fn removeSystemNow(h: *RuntimeHandle, id: abi_runtime.ke_system_id) bool {
    const systems = h.state.systems orelse return false;
    for (0..h.state.system_count) |i| {
        if (systems[i].?.id != id) continue;
        releaseSystem(systems[i].?);
        var j = i;
        while (j + 1 < h.state.system_count) : (j += 1) systems[j] = systems[j + 1];
        h.state.system_count -= 1;
        if (i < h.state.systems_prepared) h.state.systems_prepared -= 1;
        return true;
    }
    return false;
}

/// Slot `unregister_system`. Refuses, with the error set, an id that no registration has issued.
/// While a tick or a render phase is in flight the removal is pushed onto
/// `RuntimeState.pending_removals` and reported as done; it is looked up only when the next tick
/// applies it, so an id already removed passes here and is dropped there without an error.
/// Otherwise the render phase in flight is joined and the system is removed now.
fn runtimeUnregisterSystem(self: ?*abi_runtime.ke_runtime, id: abi_runtime.ke_system_id) callconv(.c) abi_result.ke_result {
    if (self == null or self.?.handle == null) {
        return R.code(reportFailure(error.InvalidArgument, "invalid argument"));
    }
    const h = handleOf(self.?);
    if (id == 0 or id > @atomicLoad(u64, &h.state.next_system_id, .monotonic)) {
        return R.code(reportFailure(error.NotFound, "no system has that id"));
    }
    if (h.state.in_tick.load(.acquire) or h.state.in_render.load(.acquire)) {
        const node = cAlloc(PendingRemoval, 1) orelse {
            return R.code(reportFailure(error.OutOfMemory, "removal record allocation failed"));
        };
        node[0] = .{ .id = id, .next = null };
        var head = h.state.pending_removals.load(.acquire);
        while (true) {
            node[0].next = head;
            head = h.state.pending_removals.cmpxchgWeak(head, &node[0], .release, .acquire) orelse return R.ok;
        }
    }
    _ = runtimeJoinPendingRender(h);
    if (removeSystemNow(h, id)) return R.ok;
    return R.code(reportFailure(error.NotFound, "no system has that id"));
}

/// Slot `last_system`. Returns the id of the last system in the list, or zero when the list is
/// empty. A system still waiting in `RuntimeState.pending_systems` is not in the list and is not
/// counted.
fn runtimeLastSystem(self: ?*abi_runtime.ke_runtime) callconv(.c) abi_runtime.ke_system_id {
    if (self == null or self.?.handle == null) return 0;
    const h = handleOf(self.?);
    const systems = h.state.systems orelse return 0;
    if (h.state.system_count == 0) return 0;
    return systems[h.state.system_count - 1].?.id;
}

/// The work one scheduler task runs: one slice of one system, with its own context, commands and
/// queue. `ctx` refers to `commands` and `state`, and its address is handed to the scheduler, so
/// the package stays in its slot until the wave has been waited for.
const TaskPkg = struct {
    state: CtxState,
    ctx: abi_runtime.ke_system_ctx,
    commands: abi_ecs.ke_ecs_commands,
    execute: ?*const fn (?*abi_runtime.ke_system_ctx, ?*anyopaque, f32) callconv(.c) abi_result.ke_result,
    user_data: ?*anyopaque,
    dt: f32,
    defer_q: DeferQueue,
    allow_defer: bool,
    name: [*c]const u8,
};

/// The first failure of a phase or of a wave: the code and the name of the system that returned
/// it. The code is OK and the name null when there is no failure. `firstOf` keeps the earlier one
/// when both failed.
const PhaseFailure = struct {
    code: abi_result.ke_result = R.ok,
    system: [*c]const u8 = null,

    fn failed(self: PhaseFailure) bool {
        return self.code != R.ok;
    }

    fn firstOf(self: PhaseFailure, other: PhaseFailure) PhaseFailure {
        return if (self.failed()) self else other;
    }
};

/// The scheduler task body for one package, run on a worker. The body's code is what crosses to
/// the waiting thread.
fn taskPkgRun(data: ?*anyopaque) callconv(.c) abi_result.ke_result {
    const pkg: *TaskPkg = @ptrCast(@alignCast(data.?));
    if (pkg.allow_defer) pkg.state.defer_q = &pkg.defer_q;
    return pkg.execute.?(&pkg.ctx, pkg.user_data, pkg.dt);
}

/// What `runWaveBody` needs for one wave: the packages built for it, a task slot for each, and
/// their number. The arrays are the runtime's per-phase scratch.
const WaveRunCtx = struct {
    h: *RuntimeHandle,
    pkgs: [*]TaskPkg,
    tasks: [*]?*abi_scheduler.ke_task,
    wave_size: u32,
};

/// Dispatches every package of the wave, then waits for all of them, including after one has failed. The failure it returns is
/// the first in package order, with the name of its system.
fn runWaveBody(wc: *WaveRunCtx) PhaseFailure {
    const sched = wc.h.state.scheduler;
    var t: u32 = 0;
    while (t < wc.wave_size) : (t += 1) {
        wc.tasks[t] = sched.dispatch.?(sched, taskPkgRun, &wc.pkgs[t]);
    }
    var failure = PhaseFailure{};
    t = 0;
    while (t < wc.wave_size) : (t += 1) {
        const code = sched.wait.?(sched, wc.tasks[t]);
        if (code == R.ok or failure.failed()) continue;
        failure = .{
            .code = code,
            .system = wc.pkgs[t].state.system_name,
        };
    }
    return failure;
}

/// Frees the per-phase arrays that `ke_runtime_create` allocated, each holding
/// `max_systems_per_phase` entries per phase, and the extraction scratch. It runs when creation
/// fails and at teardown.
fn freePhaseScratch(h: *RuntimeHandle) void {
    h.state.extract_scratch.free();
    const n: usize = @as(usize, h.state.max_systems_per_phase) * KE_RUNTIME_PHASE_COUNT;
    cFree(u32, h.state.phase_indices, n);
    cFree(abi_runtime.ke_runtime_system_params, h.state.phase_params, n);
    cFree(u32, h.state.wave_assignments, n);
    cFree(TaskPkg, h.state.phase_pkgs, n);
    cFree(?*abi_scheduler.ke_task, h.state.phase_tasks, n);
    h.state.phase_indices = null;
    h.state.phase_params = null;
    h.state.wave_assignments = null;
    h.state.phase_pkgs = null;
    h.state.phase_tasks = null;
}

/// The failure that names a system whose segment or extraction buffers could not be allocated.
fn segmentAllocationFailed(rs: *const RegisteredSystem) PhaseFailure {
    return .{ .code = R.code(error.OutOfMemory), .system = rs.params.name };
}

/// The failure that names a system whose query could not be resolved.
fn resolveFailed(rs: *const RegisteredSystem, err: R.Error) PhaseFailure {
    log.warn("resolving a query of {s} failed: {t}", .{ std.mem.span(rs.params.name.?), err });
    return .{ .code = R.code(err), .system = rs.params.name };
}

/// Runs one phase wave by wave until it finishes or its first failure stops it. The systems of
/// the phase are taken in registration order and cut into waves by `debugComputeWaves`; each
/// wave's queries are resolved on the calling thread, one package per slice of each system is
/// dispatched, and the queues are flushed after the wave's barrier. No wave starts after a failed
/// one. For the render phase it raises `in_render` for the whole run, which makes registrations
/// wait, and resolves no query. A phase with no systems returns no failure, and so does a call
/// whose scratch arrays were never allocated; the latter is not reported.
fn runtimeRunPhase(h: *RuntimeHandle, phase: abi_runtime.ke_phase, dt: f32) PhaseFailure {
    if (phase == abi_runtime.KE_PHASE_RENDER) h.state.in_render.store(true, .release);
    defer if (phase == abi_runtime.KE_PHASE_RENDER) h.state.in_render.store(false, .release);
    if (h.state.system_count == 0) return .{};

    const cap: usize = h.state.max_systems_per_phase;
    const base: usize = @as(usize, @intCast(phase)) * cap;
    const phase_indices = (h.state.phase_indices orelse return .{}) + base;
    const phase_params = (h.state.phase_params orelse return .{}) + base;
    var phase_count: u32 = 0;
    for (0..h.state.system_count) |si| {
        const rs = h.state.systems.?[si].?;
        if (rs.params.phase != phase) continue;
        if (rs.params.execute == null) continue;
        if (phase_count >= h.state.max_systems_per_phase) break;
        phase_indices[phase_count] = @intCast(si);
        phase_params[phase_count] = rs.params;
        phase_count += 1;
    }
    if (phase_count == 0) return .{};

    const wave_assignments = (h.state.wave_assignments orelse return .{}) + base;
    const ordered = orderPhase(h, phase_indices[0..phase_count], wave_assignments[0..phase_count]);
    if (orderFailure(ordered.failure)) |f| return f;
    const wave_count = ordered.wave_count;

    const pkgs = (h.state.phase_pkgs orelse return .{}) + base;
    const tasks = (h.state.phase_tasks orelse return .{}) + base;

    var failure = PhaseFailure{};
    var w: u32 = 0;
    while (w < wave_count) : (w += 1) {
        var wave_size: u32 = 0;

        for (0..phase_count) |k| {
            if (wave_assignments[k] != w) continue;
            const rs = h.state.systems.?[phase_indices[k]].?;

            if (rs.query_count > 0 and phase != abi_runtime.KE_PHASE_RENDER and h.state.ecs.query_resolve != null) {
                for (0..rs.query_count) |q| {
                    rs.seg_counts[q] = resolveInto(h.state.ecs, rs.query_ids[q], &rs.segs[q], rs.query_decls[q].term_count) catch |err| return resolveFailed(rs, err);
                    rs.seg_ptrs[q] = rs.segs[q].ptr;
                }
            }

            const slices = sliceCountFor(h, &rs.params, h.state.max_systems_per_phase - wave_size);
            var slice: u32 = 0;
            while (slice < slices) : (slice += 1) {
                const pkg = &pkgs[wave_size];
                bindCtx(&pkg.ctx, &pkg.commands, &pkg.state);
                pkg.state.ecs = h.state.ecs;
                pkg.state.access_list = rs.params.access_list;
                pkg.state.access_count = rs.params.access_count;
                pkg.state.system_name = rs.params.name;
                pkg.state.defer_q = null;
                pkg.state.slice_index = slice;
                pkg.state.slice_count = slices;

                if (rs.query_count > 0) {
                    pkg.state.seg_ptrs = rs.seg_ptrs.ptr;
                    pkg.state.seg_counts = rs.seg_counts.ptr;
                    pkg.state.view_query_count = rs.query_count;
                } else {
                    pkg.state.seg_ptrs = null;
                    pkg.state.seg_counts = null;
                    pkg.state.view_query_count = 0;
                }
                pkg.execute = rs.params.execute;
                pkg.name = rs.params.name;
                pkg.user_data = rs.params.user_data;
                pkg.dt = dt;
                pkg.defer_q = .{};
                pkg.allow_defer = phase != abi_runtime.KE_PHASE_RENDER;
                wave_size += 1;
            }
        }

        var wc = WaveRunCtx{ .h = h, .pkgs = pkgs, .tasks = tasks, .wave_size = wave_size };
        failure = failure.firstOf(runWaveBody(&wc));

        var t: u32 = 0;
        while (t < wave_size) : (t += 1) {
            deferFlush(&pkgs[t].defer_q, h.state.ecs) catch |err| {
                log.warn("applying the commands of {s} failed: {t}", .{ std.mem.span(pkgs[t].name), err });
                failure = failure.firstOf(.{ .code = R.code(err), .system = pkgs[t].name });
            };
            if (pkgs[t].defer_q.cmds) |cmds| cFree(DeferCommand, cmds, pkgs[t].defer_q.capacity);
            if (pkgs[t].defer_q.arena) |arena| cFree(u8, arena, pkgs[t].defer_q.arena_capacity);
        }

        if (failure.failed()) break;
    }
    return failure;
}

/// Orders the systems at `indices`, a phase's systems in registration order, into `out_waves`.
fn orderPhase(h: *RuntimeHandle, indices: []const u32, out_waves: []u32) wave_mod.Order {
    const nodes = heap.gpa.alloc(wave_mod.Node, indices.len) catch return .{ .failure = .out_of_memory };
    defer heap.gpa.free(nodes);
    for (indices, nodes) |si, *node| {
        const rs = h.state.systems.?[si].?;
        node.* = .{ .params = &rs.params, .explicit = rs.explicit_access, .queries = rs.query_decls[0..rs.query_count] };
    }
    return wave_mod.order(nodes, h.state.rules(), out_waves);
}

/// The failure a tick reports for a phase whose order could not be built: invalid argument for an
/// unknown name or a cycle, naming the system.
fn orderFailure(problem: wave_mod.Problem) ?PhaseFailure {
    return switch (problem) {
        .none, .ambiguity => null,
        .out_of_memory => .{ .code = R.code(error.OutOfMemory), .system = "phase order" },
        .unknown_name => |u| .{ .code = R.code(error.NotFound), .system = u.system },
        .cycle => |cy| .{ .code = R.code(error.General), .system = cy.system },
    };
}

/// Slot `declare_exclusive`.
fn runtimeDeclareExclusive(self: ?*abi_runtime.ke_runtime, group: abi_ecs.ke_component_id, member: abi_ecs.ke_component_id) callconv(.c) abi_result.ke_result {
    if (self == null or self.?.handle == null or group == member) {
        return R.code(reportFailure(error.InvalidArgument, "declare_exclusive: a group and a different member are required"));
    }
    const st = &handleOf(self.?).state;
    for (st.exclusive.items) |e| {
        if (e.group == group and e.member == member) return R.ok;
    }
    st.exclusive.append(heap.gpa, .{ .group = group, .member = member }) catch {
        return R.code(reportFailure(error.OutOfMemory, "declare_exclusive: allocation failed"));
    };
    return R.ok;
}

/// Slot `declare_self_ordered`.
fn runtimeDeclareSelfOrdered(self: ?*abi_runtime.ke_runtime, cid: abi_ecs.ke_component_id) callconv(.c) abi_result.ke_result {
    if (self == null or self.?.handle == null) {
        return R.code(reportFailure(error.InvalidArgument, "invalid argument"));
    }
    const st = &handleOf(self.?).state;
    if (std.mem.indexOfScalar(abi_ecs.ke_component_id, st.self_ordered.items, cid) != null) return R.ok;
    st.self_ordered.append(heap.gpa, cid) catch {
        return R.code(reportFailure(error.OutOfMemory, "declare_self_ordered: allocation failed"));
    };
    return R.ok;
}

/// Slot `check_order`. Builds the order of each phase over the systems registered so far,
/// including those still pending, and fails on the first problem found, phase by phase, logging
/// the systems it names.
fn runtimeCheckOrder(self: ?*abi_runtime.ke_runtime, refuse_ambiguity: bool) callconv(.c) abi_result.ke_result {
    if (self == null or self.?.handle == null) {
        return R.code(reportFailure(error.InvalidArgument, "invalid argument"));
    }
    const h = handleOf(self.?);
    applyPendingSystems(h);
    const indices = heap.gpa.alloc(u32, h.state.system_count) catch {
        return R.code(reportFailure(error.OutOfMemory, "check_order: allocation failed"));
    };
    defer heap.gpa.free(indices);
    const waves = heap.gpa.alloc(u32, h.state.system_count) catch {
        return R.code(reportFailure(error.OutOfMemory, "check_order: allocation failed"));
    };
    defer heap.gpa.free(waves);
    var phase: u32 = 0;
    while (phase < KE_RUNTIME_PHASE_COUNT) : (phase += 1) {
        var count: usize = 0;
        for (0..h.state.system_count) |si| {
            if (h.state.systems.?[si].?.params.phase != phase) continue;
            indices[count] = @intCast(si);
            count += 1;
        }
        const ordered = orderPhase(h, indices[0..count], waves[0..count]);
        const problem = if (ordered.failure != .none) ordered.failure else if (refuse_ambiguity) ordered.ambiguity else .none;
        switch (problem) {
            .none => {},
            .out_of_memory => return R.code(reportFailure(error.OutOfMemory, "check_order: allocation failed")),
            .unknown_name => |u| {
                log.warn("system '{s}' names '{s}', which no system of its phase carries", .{ spanOr(u.system), spanOr(u.name) });
                return R.code(error.NotFound);
            },
            .cycle => |cy| {
                log.warn("system '{s}' is in a cycle of its phase's order", .{spanOr(cy.system)});
                return R.code(error.General);
            },
            .ambiguity => |a| {
                log.warn("systems '{s}' and '{s}' both write component {d} with no order between them", .{ spanOr(a.first), spanOr(a.second), a.cid });
                return R.code(error.General);
            },
        }
    }
    return R.ok;
}

fn spanOr(text: [*c]const u8) []const u8 {
    return if (text != null) std.mem.span(text) else "(unnamed)";
}

/// Returns how many packages a system gets in the wave being built, never more than the room left
/// in it. A system is split only when it declared per-entity work and the scheduler reports more
/// than one worker, which is read here.
fn sliceCountFor(h: *RuntimeHandle, p: *const abi_runtime.ke_runtime_system_params, room: u32) u32 {
    if (room == 0) return 0;
    if (!p.per_entity or p.exclusive) return 1;
    const sched = h.state.scheduler;
    const workers: u32 = if (sched.get_num_workers) |f| f(sched) else 0;
    if (workers <= 1) return 1;
    return @min(workers, room);
}

/// Registers with the ecs the queries of the systems from the first index up to the last, and
/// stores each id in its system. Returns the first system the ecs refuses, or whose id buffer
/// cannot be allocated, and null when all are bound. With no query registration in the ecs it binds
/// nothing and returns null.
fn runtimeBindQueries(h: *RuntimeHandle, first: usize, last: usize) ?*RegisteredSystem {
    if (h.state.ecs.query_register == null) return null;
    for (first..last) |si| {
        const rs = h.state.systems.?[si].?;
        for (0..rs.query_count) |q| {
            const qd = &rs.query_decls[q];
            const cids = heap.gpa.alloc(abi_ecs.ke_component_id, qd.term_count) catch return rs;
            defer heap.gpa.free(cids);
            for (0..qd.term_count) |t| cids[t] = qd.terms[t].cid;
            if (h.state.ecs.query_register.?(h.state.ecs, cids.ptr, qd.term_count, &rs.query_ids[q]) != abi_result.KE_OK) return rs;
        }
    }
    return null;
}

/// Called at the start of each tick. It binds the queries of the systems appended since the last
/// successful bind. The prepared count moves forward only when all of them bind, so a refused
/// system is tried again on the next tick, and the failure names it.
fn runtimePrepareSystems(h: *RuntimeHandle) PhaseFailure {
    if (h.state.systems_prepared >= h.state.system_count) return .{};
    const first = h.state.systems_prepared;
    const last = h.state.system_count;
    if (runtimeBindQueries(h, first, last)) |refused| {
        return .{ .code = R.code(error.InvalidArgument), .system = refused.params.name };
    }
    h.state.systems_prepared = last;
    return .{};
}

/// Must run only after the render phase in flight has been joined and before the next one is
/// dispatched, so no render task reads the buffers being written.
/// For each query of each render system it resolves the matches, grows the query's copy buffers
/// when the matches exceed their capacity, copies the entities and every column, and writes one
/// segment holding them all.
fn runtimeExtractRenderState(h: *RuntimeHandle) PhaseFailure {
    if (h.state.ecs.query_resolve == null) return .{};
    const scratch = &h.state.extract_scratch;

    for (0..h.state.system_count) |si| {
        const rs = h.state.systems.?[si].?;
        if (rs.params.phase != abi_runtime.KE_PHASE_RENDER) continue;

        for (0..rs.query_count) |q| {
            const eq = &rs.extracted[q];
            const qd = &rs.query_decls[q];

            if (!eq.elem_sizes_cached) {
                for (0..qd.term_count) |t| {
                    eq.col_elem_size[t] = if (h.state.ecs.component_size) |cs| cs(h.state.ecs, qd.terms[t].cid) else 0;
                }
                eq.elem_sizes_cached = true;
            }

            var raw_count: usize = 0;
            raw_count = resolveInto(h.state.ecs, rs.query_ids[q], scratch, qd.term_count) catch |err| return resolveFailed(rs, err);
            const raw = scratch.ptr.?;

            var total: usize = 0;
            for (0..raw_count) |s| total += raw[s].count;

            if (total > eq.capacity) {
                var new_cap: usize = if (eq.capacity != 0) eq.capacity * 2 else 64;
                while (new_cap < total) new_cap *= 2;

                if (cAlloc(abi_ecs.ke_entity, new_cap)) |new_ents| {
                    if (eq.entities_buf) |old| cFree(abi_ecs.ke_entity, old, eq.capacity);
                    eq.entities_buf = new_ents;

                    for (0..qd.term_count) |t| {
                        if (eq.col_elem_size[t] == 0) continue;
                        const new_col = cAllocBytes(eq.col_elem_size[t] *% new_cap) orelse return segmentAllocationFailed(rs);
                        if (eq.col_bufs[t]) |oldc| cFreeBytes(oldc, eq.col_elem_size[t] *% eq.capacity);
                        eq.col_bufs[t] = new_col;
                    }
                    eq.capacity = new_cap;
                }
                if (total > eq.capacity) return segmentAllocationFailed(rs);
            }

            const cap = eq.capacity;
            var written: usize = 0;
            var s: usize = 0;
            while (s < raw_count and written < cap) : (s += 1) {
                var take = raw[s].count;
                if (written + take > cap) take = cap - written;
                if (eq.entities_buf) |ebuf| {
                    @memcpy(ebuf[written .. written + take], raw[s].entities.?[0..take]);
                }
                for (0..qd.term_count) |t| {
                    if (eq.col_elem_size[t] == 0 or eq.col_bufs[t] == null) continue;
                    const esz = eq.col_elem_size[t];
                    const dst: [*]u8 = @ptrCast(eq.col_bufs[t].?);
                    const src: [*]const u8 = @ptrCast(raw[s].columns.?[t].?);
                    @memcpy(dst[written * esz .. written * esz + take * esz], src[0 .. take * esz]);
                }
                written += take;
            }

            eq.seg.entities = if (eq.entities_buf) |eb| eb else null;
            eq.seg.count = written;
            for (0..qd.term_count) |t| {
                eq.col_ptrs[t] = if (eq.col_elem_size[t] != 0) eq.col_bufs[t] else null;
            }
            eq.seg.columns = eq.col_ptrs.ptr;
            eq.seg.column_count = qd.term_count;

            rs.segs[q].ptr.?[0] = eq.seg;
            rs.seg_ptrs[q] = rs.segs[q].ptr;
            rs.seg_counts[q] = if (written > 0) 1 else 0;
        }
    }
    return .{};
}

/// The scheduler task body for the render phase, run on a worker. The failure stays in the job for
/// `runtimeJoinPendingRender` to read, and its code is also handed back to the scheduler.
fn renderJobRun(data: ?*anyopaque) callconv(.c) abi_result.ke_result {
    const job: *RenderJob = @ptrCast(@alignCast(data.?));
    job.failure = runtimeRunPhase(job.h, abi_runtime.KE_PHASE_RENDER, job.dt);
    return job.failure.code;
}

/// Waits for the render phase in flight, if any, and returns the failure it recorded. The record is
/// cleared when read, so a failure is returned once.
fn runtimeJoinPendingRender(h: *RuntimeHandle) PhaseFailure {
    const task = h.state.pending_render_task orelse return .{};
    _ = h.state.scheduler.wait.?(h.state.scheduler, task);
    h.state.pending_render_task = null;
    const job = h.state.render_job orelse return .{};
    const failure = job.failure;
    job.failure = .{};
    return failure;
}

/// Slot `tick`. It applies the pending system changes before raising `in_tick`, so a
/// registration made from inside the tick waits for the next one, and it lowers `in_tick` on
/// return, failure included.
fn runtimeTick(self: ?*abi_runtime.ke_runtime, dt: f32) callconv(.c) abi_result.ke_result {
    if (self == null or self.?.handle == null) {
        return R.code(reportFailure(error.InvalidArgument, "invalid argument"));
    }
    const h = handleOf(self.?);
    applyPendingSystems(h);
    h.state.in_tick.store(true, .release);
    defer h.state.in_tick.store(false, .release);
    return runtimeTickBody(self, dt);
}

/// Runs the sim phases of one tick, then joins the previous render phase, extracts the render
/// state and dispatches the next render phase, which it does not wait for. Returns at the first
/// failing step, with invalid argument for a null runtime or a negative dt and otherwise with the
/// code of the failure, whose system is logged. The render phase in flight is joined before a
/// failure is reported, and a failed tick dispatches no render phase. The startup phase is marked
/// started before it runs, so a startup that fails is not run again. Without a render job record
/// the render phase runs inline and its failure is reported here.
fn runtimeTickBody(self: ?*abi_runtime.ke_runtime, dt: f32) abi_result.ke_result {
    if (self == null or self.?.handle == null) {
        return R.code(reportFailure(error.InvalidArgument, "invalid argument"));
    }
    if (dt < 0.0) {
        return R.code(reportFailure(error.InvalidArgument, "negative dt"));
    }
    const h = handleOf(self.?);

    var failure = runtimePrepareSystems(h);
    if (!failure.failed() and !h.state.started) {
        h.state.started = true;
        failure = runtimeRunPhase(h, abi_runtime.KE_PHASE_STARTUP, 0.0);
    }
    if (!failure.failed()) failure = runtimeRunPhase(h, abi_runtime.KE_PHASE_PRE_UPDATE, dt);

    h.state.fixed_accumulator += dt;
    if (h.state.fixed_accumulator > h.state.fixed_dt_max_accum) {
        h.state.fixed_accumulator = h.state.fixed_dt_max_accum;
    }
    while (!failure.failed() and h.state.fixed_accumulator >= h.state.fixed_dt) {
        for ([_]abi_runtime.ke_phase{ abi_runtime.KE_PHASE_FIXED_PRE_UPDATE, abi_runtime.KE_PHASE_FIXED_UPDATE, abi_runtime.KE_PHASE_FIXED_POST_UPDATE }) |phase| {
            if (!failure.failed()) failure = runtimeRunPhase(h, phase, h.state.fixed_dt);
        }
        h.state.fixed_accumulator -= h.state.fixed_dt;
    }

    if (!failure.failed()) failure = runtimeRunPhase(h, abi_runtime.KE_PHASE_UPDATE, dt);
    if (!failure.failed()) failure = runtimeRunPhase(h, abi_runtime.KE_PHASE_POST_UPDATE, dt);

    failure = runtimeJoinPendingRender(h).firstOf(failure);
    if (failure.failed()) return reported(failure, "a system body");

    failure = runtimeExtractRenderState(h);
    if (failure.failed()) return reported(failure, "render extraction");

    if (h.state.render_job == null) {
        if (cAlloc(RenderJob, 1)) |rj| h.state.render_job = &rj[0];
    }
    if (h.state.render_job) |job| {
        job.h = h;
        job.dt = dt;
        job.failure = .{};
        h.state.pending_render_task = h.state.scheduler.dispatch.?(h.state.scheduler, renderJobRun, job);
    } else {
        failure = runtimeRunPhase(h, abi_runtime.KE_PHASE_RENDER, dt);
        if (failure.failed()) return reported(failure, "a system body");
    }

    return R.ok;
}

/// Logs which system a phase failed in and returns its code.
fn reported(failure: PhaseFailure, comptime what: []const u8) abi_result.ke_result {
    log.warn(what ++ " failed in {s}", .{spanOr(failure.system)});
    return failure.code;
}

/// Slot `flush_render`. Waits for the render phase dispatched by the last tick and reports its
/// failure. A tick returns
/// before that phase finishes, so a failure of the phase reaches the caller only here or at the
/// next tick.
fn runtimeFlushRender(self: ?*abi_runtime.ke_runtime) callconv(.c) abi_result.ke_result {
    if (self == null or self.?.handle == null) {
        return R.code(reportFailure(error.InvalidArgument, "invalid argument"));
    }
    const failure = runtimeJoinPendingRender(handleOf(self.?));
    if (failure.failed()) return reported(failure, "a system body");
    return R.ok;
}

/// The handle's `destroy`. It joins the render phase, runs `KE_PHASE_SHUTDOWN` if the runtime
/// ever started, unloads the modules in reverse order of registration, and releases the pending and
/// registered systems and the scratch. The ecs and the scheduler are not touched.
fn runtimeDestroy(self: ?*abi_runtime.ke_runtime) callconv(.c) void {
    if (self == null or self.?.handle == null) return;
    const h = handleOf(self.?);

    _ = runtimeJoinPendingRender(h);

    if (h.state.started) _ = runtimeRunPhase(h, abi_runtime.KE_PHASE_SHUTDOWN, 0.0);

    if (h.state.modules) |modules| {
        var i = h.state.module_count;
        while (i > 0) {
            i -= 1;
            if (modules[i].on_unload) |unload| unload(self, modules[i].user_data);
        }
        cFree(RegisteredModule, modules, h.state.module_capacity);
    }

    if (h.state.render_job) |rj| cFree(RenderJob, @ptrCast(rj), 1);

    var stranded_removals = h.state.pending_removals.swap(null, .acq_rel);
    while (stranded_removals) |r| {
        stranded_removals = r.next;
        cFree(PendingRemoval, @ptrCast(r), 1);
    }
    var stranded = h.state.pending_systems.swap(null, .acq_rel);
    while (stranded) |rs| {
        stranded = rs.pending_next;
        releaseSystem(rs);
    }

    if (h.state.systems) |systems| {
        for (0..h.state.system_count) |i| {
            const rs = systems[i].?;
            releaseSystem(rs);
        }
        cFree(?*RegisteredSystem, systems, h.state.system_capacity);
    }
    freePhaseScratch(h);
    h.state.exclusive.deinit(heap.gpa);
    h.state.self_ordered.deinit(heap.gpa);
    cFree(RuntimeHandle, @ptrCast(h), 1);
}

/// The factory. Creates a runtime over an ecs and a scheduler that it does not own: it keeps the
/// pointers and never frees them. A null ecs or scheduler fails with `invalid_argument`, and an
/// allocation failure with `out_of_memory`. The params pointer may be null, and a zero in
/// `fixed_dt`, `fixed_dt_max_accum` or `max_systems_per_phase` takes that field's default. The
/// per-phase scratch arrays are allocated here, and if that fails the result is an empty handle
/// with the error set.
export fn ke_runtime_create(ecs: ?*abi_ecs.ke_ecs, scheduler: ?*abi_scheduler.ke_scheduler, params: [*c]const abi_runtime_factory.ke_runtime_params, out_runtime: ?*abi_runtime.ke_runtime_handle) callconv(.c) abi_result.ke_result {
    const out = out_runtime orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    if (ecs == null or scheduler == null) {
        return R.code(reportFailure(error.InvalidArgument, "creating the runtime needs an ecs and a scheduler"));
    }

    const h_mem = cAlloc(RuntimeHandle, 1) orelse {
        return R.code(reportFailure(error.OutOfMemory, "creating the runtime failed: out of memory"));
    };
    const h = &h_mem[0];
    @memset(std.mem.asBytes(h), 0);

    h.state.ecs = ecs.?;
    h.state.scheduler = scheduler.?;
    h.state.exclusive = .empty;
    h.state.self_ordered = .empty;

    h.state.fixed_dt = if (params != null and params.*.fixed_dt > 0.0) params.*.fixed_dt else (1.0 / 60.0);
    h.state.fixed_dt_max_accum = if (params != null and params.*.fixed_dt_max_accum > 0.0) params.*.fixed_dt_max_accum else 0.25;

    const max_per_phase: u32 = if (params != null and params.*.max_systems_per_phase > 0) params.*.max_systems_per_phase else 256;
    h.state.max_systems_per_phase = max_per_phase;
    h.state.extract_scratch = .{};
    const n: usize = @as(usize, max_per_phase) * KE_RUNTIME_PHASE_COUNT;
    h.state.phase_indices = cAlloc(u32, n);
    h.state.phase_params = cAlloc(abi_runtime.ke_runtime_system_params, n);
    h.state.wave_assignments = cAlloc(u32, n);
    h.state.phase_pkgs = cAlloc(TaskPkg, n);
    h.state.phase_tasks = cAlloc(?*abi_scheduler.ke_task, n);
    if (h.state.phase_indices == null or h.state.phase_params == null or h.state.wave_assignments == null or
        h.state.phase_pkgs == null or h.state.phase_tasks == null)
    {
        freePhaseScratch(h);
        cFree(RuntimeHandle, @ptrCast(h), 1);
        return R.code(reportFailure(error.OutOfMemory, "creating the runtime failed: out of memory"));
    }

    h.api.handle = h;
    h.api.register_module = &runtimeRegisterModule;
    h.api.register_system = &runtimeRegisterSystem;
    h.api.unregister_system = &runtimeUnregisterSystem;
    h.api.last_system = &runtimeLastSystem;
    h.api.declare_exclusive = &runtimeDeclareExclusive;
    h.api.declare_self_ordered = &runtimeDeclareSelfOrdered;
    h.api.check_order = &runtimeCheckOrder;
    h.api.tick = &runtimeTick;
    h.api.flush_render = &runtimeFlushRender;

    out.* = .{ .ref = &h.api, .destroy = &runtimeDestroy };
    return R.ok;
}

const testing = std.testing;

fn systemId(rt: [*c]abi_runtime.ke_runtime, p: [*c]const abi_runtime.ke_runtime_system_params) abi_runtime.ke_system_id {
    var id: abi_runtime.ke_system_id = 0;
    _ = rt.*.register_system.?(rt, p, &id);
    return id;
}

fn loadedModule(rt: [*c]abi_runtime.ke_runtime, p: [*c]const abi_runtime.ke_runtime_module_params) abi_runtime.ke_module_id {
    var id: abi_runtime.ke_module_id = 0;
    _ = rt.*.register_module.?(rt, p, &id);
    return id;
}

fn ticked(rt: [*c]abi_runtime.ke_runtime, dt: f32) bool {
    return rt.*.tick.?(rt, dt) == R.ok;
}

fn spawned(commands: [*c]abi_ecs.ke_ecs_commands) abi_ecs.ke_entity {
    var entity: abi_ecs.ke_entity = abi_ecs.KE_ENTITY_INVALID;
    _ = commands.*.spawn.?(commands, &entity);
    return entity;
}

fn createdRuntime(ecs: ?*abi_ecs.ke_ecs, scheduler: ?*abi_scheduler.ke_scheduler, params: [*c]const abi_runtime_factory.ke_runtime_params) abi_runtime.ke_runtime_handle {
    var h: abi_runtime.ke_runtime_handle = .{ .ref = null, .destroy = null };
    _ = ke_runtime_create(ecs, scheduler, params, &h);
    return h;
}

extern fn ke_ecs_flecs_create(params: ?*const anyopaque, out_ecs: *abi_ecs.ke_ecs_handle) callconv(.c) abi_result.ke_result;
extern fn ke_scheduler_enki_create(params: ?*const anyopaque, out_scheduler: *abi_scheduler.ke_scheduler_handle) callconv(.c) abi_result.ke_result;

fn ecsSpawn(ecs: *abi_ecs.ke_ecs) R.Error!abi_ecs.ke_entity {
    var entity: abi_ecs.ke_entity = 0;
    try R.check(ecs.entity_create.?(ecs, &entity));
    return entity;
}

fn ecsAttach(ecs: *abi_ecs.ke_ecs, entity: abi_ecs.ke_entity, cid: abi_ecs.ke_component_id) R.Error!?*anyopaque {
    var data: ?*anyopaque = null;
    try R.check(ecs.component_add.?(ecs, entity, cid, &data));
    return data;
}

const Fixture = struct {
    scheduler_h: abi_scheduler.ke_scheduler_handle,
    ecs_h: abi_ecs.ke_ecs_handle,
    runtime_h: abi_runtime.ke_runtime_handle,

    fn init() !Fixture {
        var sh: abi_scheduler.ke_scheduler_handle = undefined;
        try R.check(ke_scheduler_enki_create(null, &sh));

        var eh: abi_ecs.ke_ecs_handle = undefined;
        try R.check(ke_ecs_flecs_create(null, &eh));

        var rp = std.mem.zeroes(abi_runtime_factory.ke_runtime_params);
        const rh = createdRuntime(eh.ref, sh.ref, &rp);
        try testing.expect(rh.ref != null);

        return .{ .scheduler_h = sh, .ecs_h = eh, .runtime_h = rh };
    }

    fn deinit(self: *Fixture) void {
        if (self.runtime_h.ref) |r| self.runtime_h.destroy.?(r);
        if (self.ecs_h.ref) |r| self.ecs_h.destroy.?(r);
        if (self.scheduler_h.ref) |r| self.scheduler_h.destroy.?(r);
    }

    fn rt(self: *Fixture) *abi_runtime.ke_runtime {
        return @ptrCast(self.runtime_h.ref);
    }

    fn ecs(self: *Fixture) *abi_ecs.ke_ecs {
        return @ptrCast(self.ecs_h.ref);
    }

    fn tick(self: *Fixture, dt: f32) bool {
        return ticked(self.rt(), dt);
    }

    fn flushRender(self: *Fixture) void {
        _ = (self.rt().flush_render.?(self.rt()) == R.ok);
    }
};

fn queryOf(terms: []const abi_runtime.ke_component_access) abi_runtime.ke_query_decl {
    return .{ .terms = terms.ptr, .term_count = @intCast(terms.len) };
}

fn withQueries(sys: *abi_runtime.ke_runtime_system_params, decls: []const abi_runtime.ke_query_decl) void {
    sys.queries = decls.ptr;
    sys.query_count = @intCast(decls.len);
}

fn access(cid: u32, mode: c_int) abi_runtime.ke_component_access {
    return .{ .cid = cid, .access = @intCast(mode) };
}

fn systemParams(name: [*c]const u8, phase: c_int) abi_runtime.ke_runtime_system_params {
    var s = std.mem.zeroes(abi_runtime.ke_runtime_system_params);
    s.name = name;
    s.phase = @intCast(phase);
    return s;
}

fn noopSystem(_: ?*abi_runtime.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    return R.ok;
}

fn refusingSystem(_: ?*abi_runtime.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    return R.code(error.NotSupported);
}

const Counter = std.atomic.Value(u32);

fn countingSystem(_: ?*abi_runtime.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const counter: *Counter = @ptrCast(@alignCast(ud.?));
    _ = counter.fetchAdd(1, .acq_rel);
    return R.ok;
}

const ModuleCtx = struct {
    load_calls: Counter = Counter.init(0),
    system_ticks: Counter = Counter.init(0),
};

fn moduleTickSystem(_: ?*abi_runtime.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const ctx: *ModuleCtx = @ptrCast(@alignCast(ud.?));
    _ = ctx.system_ticks.fetchAdd(1, .acq_rel);
    return R.ok;
}

fn testModuleOnLoad(runtime: ?*abi_runtime.ke_runtime, ud: ?*anyopaque) callconv(.c) abi_result.ke_result {
    const ctx: *ModuleCtx = @ptrCast(@alignCast(ud.?));
    _ = ctx.load_calls.fetchAdd(1, .acq_rel);

    var sys = systemParams("TickCounter", abi_runtime.KE_PHASE_UPDATE);
    sys.user_data = ud;
    sys.execute = &moduleTickSystem;

    const rtp = runtime orelse return R.code(error.General);
    return if (systemId(rtp, &sys) != 0) R.ok else R.code(error.General);
}

const UnloadRecorder = struct {
    seen: [4]u32 = [_]u32{0} ** 4,
    count: usize = 0,
};

const OrderedModule = struct {
    recorder: *UnloadRecorder,
    tag: u32,
};

fn orderedOnLoad(_: ?*abi_runtime.ke_runtime, _: ?*anyopaque) callconv(.c) abi_result.ke_result {
    return R.ok;
}

fn refusingOnLoad(_: ?*abi_runtime.ke_runtime, _: ?*anyopaque) callconv(.c) abi_result.ke_result {
    return R.code(error.InvalidArgument);
}

fn orderedOnUnload(_: ?*abi_runtime.ke_runtime, ud: ?*anyopaque) callconv(.c) void {
    const m: *OrderedModule = @ptrCast(@alignCast(ud.?));
    m.recorder.seen[m.recorder.count] = m.tag;
    m.recorder.count += 1;
}

const SliceProbe = struct {
    calls: Counter = Counter.init(0),
    seen: [64]Counter = [_]Counter{Counter.init(0)} ** 64,
    reported_count: Counter = Counter.init(0),
};

fn sliceProbeSystem(ctx: ?*abi_runtime.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const probe: *SliceProbe = @ptrCast(@alignCast(ud.?));
    var index: u32 = 99;
    var count: u32 = 99;
    ctx.?.slice.?(ctx, &index, &count);
    _ = probe.calls.fetchAdd(1, .acq_rel);
    probe.reported_count.store(count, .release);
    if (index < probe.seen.len) _ = probe.seen[index].fetchAdd(1, .acq_rel);
    return R.ok;
}

test "a system that does not promise per-entity work runs as one slice" {
    var f = try Fixture.init();
    defer f.deinit();

    var probe = SliceProbe{};
    var sys = systemParams("Serial", abi_runtime.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &sliceProbeSystem;
    try testing.expect(systemId(f.rt(), &sys) != 0);

    try testing.expect(f.tick(1.0 / 60.0));

    try testing.expectEqual(@as(u32, 1), probe.calls.load(.acquire));
    try testing.expectEqual(@as(u32, 1), probe.reported_count.load(.acquire));
    try testing.expectEqual(@as(u32, 1), probe.seen[0].load(.acquire));
}

test "a per-entity system runs every slice of its set exactly once" {
    var f = try Fixture.init();
    defer f.deinit();

    var probe = SliceProbe{};
    var sys = systemParams("Sliced", abi_runtime.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &sliceProbeSystem;
    sys.per_entity = true;
    try testing.expect(systemId(f.rt(), &sys) != 0);

    try testing.expect(f.tick(1.0 / 60.0));

    const slices = probe.reported_count.load(.acquire);
    try testing.expect(slices >= 1);
    try testing.expectEqual(slices, probe.calls.load(.acquire));

    var i: u32 = 0;
    while (i < slices) : (i += 1)
        try testing.expectEqual(@as(u32, 1), probe.seen[i].load(.acquire));
}

test "a runtime with no systems ticks and tears down" {
    var f = try Fixture.init();
    defer f.deinit();

    try testing.expect(f.tick(1.0 / 60.0));
}

test "registering a module calls its load hook exactly once" {
    var f = try Fixture.init();
    defer f.deinit();

    var ctx = ModuleCtx{};
    var mod = std.mem.zeroes(abi_runtime.ke_runtime_module_params);
    mod.name = "TestModule";
    mod.user_data = &ctx;
    mod.on_load = &testModuleOnLoad;

    const mid = loadedModule(f.rt(), &mod);
    try testing.expect(mid != 0);
    try testing.expectEqual(@as(u32, 1), ctx.load_calls.load(.acquire));
}

test "a registered system fires once per tick" {
    var f = try Fixture.init();
    defer f.deinit();

    var ctx = ModuleCtx{};
    var mod = std.mem.zeroes(abi_runtime.ke_runtime_module_params);
    mod.name = "TickModule";
    mod.user_data = &ctx;
    mod.on_load = &testModuleOnLoad;

    try testing.expect(loadedModule(f.rt(), &mod) != 0);

    for (0..10) |_| try testing.expect(f.tick(1.0 / 60.0));

    try testing.expectEqual(@as(u32, 10), ctx.system_ticks.load(.acquire));
}

test "a module's unload hook runs when the runtime is destroyed" {
    var recorder = UnloadRecorder{};
    var only = OrderedModule{ .recorder = &recorder, .tag = 7 };

    var f = try Fixture.init();
    var mod = std.mem.zeroes(abi_runtime.ke_runtime_module_params);
    mod.name = "UnloadModule";
    mod.user_data = &only;
    mod.on_load = &orderedOnLoad;
    mod.on_unload = &orderedOnUnload;

    try testing.expect(loadedModule(f.rt(), &mod) != 0);
    try testing.expectEqual(@as(usize, 0), recorder.count);

    f.deinit();

    try testing.expectEqual(@as(usize, 1), recorder.count);
    try testing.expectEqual(@as(u32, 7), recorder.seen[0]);
}

test "modules unload in reverse registration order" {
    var recorder = UnloadRecorder{};
    var first = OrderedModule{ .recorder = &recorder, .tag = 1 };
    var second = OrderedModule{ .recorder = &recorder, .tag = 2 };
    var third = OrderedModule{ .recorder = &recorder, .tag = 3 };

    var f = try Fixture.init();
    for ([_]*OrderedModule{ &first, &second, &third }) |m| {
        var mod = std.mem.zeroes(abi_runtime.ke_runtime_module_params);
        mod.name = "Ordered";
        mod.user_data = m;
        mod.on_load = &orderedOnLoad;
        mod.on_unload = &orderedOnUnload;
        try testing.expect(loadedModule(f.rt(), &mod) != 0);
    }

    f.deinit();

    try testing.expectEqual(@as(usize, 3), recorder.count);
    try testing.expectEqualSlices(u32, &[_]u32{ 3, 2, 1 }, recorder.seen[0..3]);
}

test "a module whose load failed is not unloaded" {
    var recorder = UnloadRecorder{};
    var loaded = OrderedModule{ .recorder = &recorder, .tag = 1 };
    var refused = OrderedModule{ .recorder = &recorder, .tag = 2 };

    var f = try Fixture.init();

    var good = std.mem.zeroes(abi_runtime.ke_runtime_module_params);
    good.name = "Loads";
    good.user_data = &loaded;
    good.on_load = &orderedOnLoad;
    good.on_unload = &orderedOnUnload;
    try testing.expect(loadedModule(f.rt(), &good) != 0);

    var bad = std.mem.zeroes(abi_runtime.ke_runtime_module_params);
    bad.name = "Refuses";
    bad.user_data = &refused;
    bad.on_load = &refusingOnLoad;
    bad.on_unload = &orderedOnUnload;
    try testing.expectEqual(@as(abi_runtime.ke_module_id, 0), loadedModule(f.rt(), &bad));

    f.deinit();

    try testing.expectEqual(@as(usize, 1), recorder.count);
    try testing.expectEqual(@as(u32, 1), recorder.seen[0]);
}

test "registering a module with no params is refused" {
    var f = try Fixture.init();
    defer f.deinit();

    try testing.expectEqual(@as(abi_runtime.ke_module_id, 0), loadedModule(f.rt(), null));
}

test "a body that fails the tick keeps the later phases from running" {
    var f = try Fixture.init();
    defer f.deinit();

    var counter = Counter.init(0);

    var boom = systemParams("Boom", abi_runtime.KE_PHASE_PRE_UPDATE);
    boom.execute = &refusingSystem;
    try testing.expect(systemId(f.rt(), &boom) != 0);

    var later = systemParams("Later", abi_runtime.KE_PHASE_POST_UPDATE);
    later.execute = &countingSystem;
    later.user_data = &counter;
    try testing.expect(systemId(f.rt(), &later) != 0);

    try testing.expectError(error.NotSupported, R.check(f.rt().tick.?(f.rt(), 1.0 / 60.0)));
    try testing.expectEqual(@as(u32, 0), counter.load(.acquire));
}

test "registering a system with no execute body is refused" {
    var f = try Fixture.init();
    defer f.deinit();

    const sys = systemParams("Bad", abi_runtime.KE_PHASE_UPDATE);
    try testing.expectEqual(@as(abi_runtime.ke_system_id, 0), systemId(f.rt(), &sys));
}

const BareRuntime = struct {
    ecs: abi_ecs.ke_ecs = std.mem.zeroes(abi_ecs.ke_ecs),
    scheduler: abi_scheduler.ke_scheduler = std.mem.zeroes(abi_scheduler.ke_scheduler),
    runtime_h: abi_runtime.ke_runtime_handle = undefined,

    fn init(self: *BareRuntime) !void {
        var rp = std.mem.zeroes(abi_runtime_factory.ke_runtime_params);
        self.runtime_h = createdRuntime(&self.ecs, &self.scheduler, &rp);
        try testing.expect(self.runtime_h.ref != null);
    }

    fn deinit(self: *BareRuntime) void {
        self.runtime_h.destroy.?(self.runtime_h.ref.?);
    }

    fn rt(self: *BareRuntime) *abi_runtime.ke_runtime {
        return @ptrCast(self.runtime_h.ref);
    }

    fn registered(self: *BareRuntime, index: usize) *RegisteredSystem {
        return handleOf(self.rt()).state.systems.?[index].?;
    }
};

fn noopBody(_: ?*abi_runtime.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    return R.ok;
}

fn scribble(bytes: []u8) void {
    @memset(bytes, 'X');
}

test "a registered system keeps its own copy of the name" {
    var b = BareRuntime{};
    try b.init();
    defer b.deinit();

    var name_buf = [_]u8{ 'M', 'o', 'v', 'e', 0 };
    var sys = systemParams(@ptrCast(&name_buf), abi_runtime.KE_PHASE_UPDATE);
    sys.execute = &noopBody;
    try testing.expect(systemId(b.rt(), &sys) != 0);
    scribble(&name_buf);

    try testing.expectEqualStrings("Move", std.mem.span(b.registered(0).params.name.?));
}

test "a registered system keeps its own copy of the access list when it declares no query" {
    var b = BareRuntime{};
    try b.init();
    defer b.deinit();

    var list = [_]abi_runtime.ke_component_access{ access(7, abi_runtime.KE_ACCESS_WRITE), access(9, abi_runtime.KE_ACCESS_READ) };
    var sys = systemParams("Plain", abi_runtime.KE_PHASE_UPDATE);
    sys.execute = &noopBody;
    sys.access_list = &list;
    sys.access_count = list.len;
    try testing.expect(systemId(b.rt(), &sys) != 0);
    scribble(std.mem.sliceAsBytes(&list));

    const kept = b.registered(0).params;
    try testing.expectEqual(@as(usize, 2), @as(usize, kept.access_count));
    try testing.expectEqual(@as(abi_ecs.ke_component_id, 7), kept.access_list.?[0].cid);
    try testing.expectEqual(@as(abi_ecs.ke_component_id, 9), kept.access_list.?[1].cid);
}

fn lastQueryBody(ctx: ?*abi_runtime.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    var count: usize = 0;
    _ = ctx.?.view.?(ctx, 19, &count);
    seen_segments = count;
    return R.ok;
}

test "a system declaring twenty queries is resolved and viewed through every one of them" {
    var r = InlineRuntime{};
    r.bare.ecs.query_register = @ptrCast(&fakeQueryRegister);
    r.bare.ecs.query_resolve = @ptrCast(&fakeQueryResolveMany);
    r.bare.ecs.component_size = @ptrCast(&fakeComponentSize);
    try r.init();
    defer r.bare.deinit();

    var terms: [20]abi_runtime.ke_component_access = undefined;
    var decls: [20]abi_runtime.ke_query_decl = undefined;
    for (&terms, &decls) |*t, *d| {
        t.* = access(1, abi_runtime.KE_ACCESS_READ);
        d.* = queryOf(t[0..1]);
    }
    var sys = systemParams("Greedy", abi_runtime.KE_PHASE_UPDATE);
    sys.execute = &lastQueryBody;
    withQueries(&sys, &decls);
    try testing.expect(systemId(r.rt(), &sys) != 0);

    seen_segments = 0;
    try testing.expect(ticked(r.rt(), 0.001));
    try testing.expectEqual(@as(usize, many_segments), seen_segments);
}

fn termCountBody(ctx: ?*abi_runtime.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    var count: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &count);
    seen_segments = count;
    seen_entities = if (count > 0) segs.?[0].column_count else 0;
    return R.ok;
}

test "a query of twelve terms is registered and its segments carry twelve columns" {
    var r = InlineRuntime{};
    r.bare.ecs.query_register = @ptrCast(&fakeQueryRegister);
    r.bare.ecs.query_resolve = @ptrCast(&fakeQueryResolveMany);
    r.bare.ecs.component_size = @ptrCast(&fakeComponentSize);
    try r.init();
    defer r.bare.deinit();

    var terms: [12]abi_runtime.ke_component_access = undefined;
    for (&terms, 0..) |*t, i| t.* = access(@intCast(i + 1), abi_runtime.KE_ACCESS_READ);
    var sys = systemParams("Wide", abi_runtime.KE_PHASE_UPDATE);
    sys.execute = &termCountBody;
    withQueries(&sys, &.{queryOf(&terms)});
    try testing.expect(systemId(r.rt(), &sys) != 0);

    fake_term_count = 12;
    defer fake_term_count = 1;
    seen_segments = 0;
    try testing.expect(ticked(r.rt(), 0.001));
    try testing.expectEqual(@as(usize, many_segments), seen_segments);
    try testing.expectEqual(@as(usize, 12), seen_entities);
}

test "a query counting terms it does not point at is refused" {
    var b = BareRuntime{};
    try b.init();
    defer b.deinit();

    var sys = systemParams("Dangling", abi_runtime.KE_PHASE_UPDATE);
    sys.execute = &noopBody;
    const decls = [_]abi_runtime.ke_query_decl{.{ .terms = null, .term_count = 2 }};
    withQueries(&sys, &decls);

    try testing.expectEqual(@as(abi_runtime.ke_system_id, 0), systemId(b.rt(), &sys));
}

test "a query declaring no terms is refused" {
    var b = BareRuntime{};
    try b.init();
    defer b.deinit();

    var sys = systemParams("Empty", abi_runtime.KE_PHASE_UPDATE);
    sys.execute = &noopBody;
    var terms = [_]abi_runtime.ke_component_access{};
    withQueries(&sys, &.{queryOf(&terms)});

    try testing.expectEqual(@as(abi_runtime.ke_system_id, 0), systemId(b.rt(), &sys));
}

var inline_result: abi_result.ke_result = R.ok;
var inline_token: u8 = 0;

fn inlineDispatch(_: [*c]abi_scheduler.ke_scheduler, func: abi_scheduler.ke_task_func, data: ?*anyopaque) callconv(.c) ?*abi_scheduler.ke_task {
    inline_result = func.?(data);
    return @ptrCast(&inline_token);
}

fn inlineWait(_: [*c]abi_scheduler.ke_scheduler, _: ?*abi_scheduler.ke_task) callconv(.c) abi_result.ke_result {
    return inline_result;
}

const InlineRuntime = struct {
    bare: BareRuntime = .{},

    fn init(self: *InlineRuntime) !void {
        self.bare.scheduler.dispatch = @ptrCast(&inlineDispatch);
        self.bare.scheduler.wait = @ptrCast(&inlineWait);
        try self.bare.init();
    }

    fn rt(self: *InlineRuntime) *abi_runtime.ke_runtime {
        return self.bare.rt();
    }
};

const PhaseLog = struct {
    seen: [16]c_int = undefined,
    count: usize = 0,
};

fn phaseLogBody(ctx: ?*abi_runtime.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    _ = ctx;
    const entry: *const PhaseLogEntry = @ptrCast(@alignCast(ud.?));
    entry.log.seen[entry.log.count] = entry.phase;
    entry.log.count += 1;
    return R.ok;
}

const PhaseLogEntry = struct {
    log: *PhaseLog,
    phase: c_int,
};

test "the startup phase runs once, before the first tick's other phases" {
    var r = InlineRuntime{};
    try r.init();

    var seen_log = PhaseLog{};
    const phases = [_]c_int{ abi_runtime.KE_PHASE_UPDATE, abi_runtime.KE_PHASE_STARTUP, abi_runtime.KE_PHASE_PRE_UPDATE };
    var entries: [phases.len]PhaseLogEntry = undefined;
    for (phases, 0..) |ph, i| {
        entries[i] = .{ .log = &seen_log, .phase = ph };
        var sys = systemParams("Logged", ph);
        sys.execute = &phaseLogBody;
        sys.user_data = &entries[i];
        try testing.expect(systemId(r.rt(), &sys) != 0);
    }

    for (0..3) |_| try testing.expect(ticked(r.rt(), 0.001));
    r.bare.deinit();

    try testing.expectEqual(@as(c_int, abi_runtime.KE_PHASE_STARTUP), seen_log.seen[0]);
    var startups: usize = 0;
    for (seen_log.seen[0..seen_log.count]) |ph| {
        if (ph == abi_runtime.KE_PHASE_STARTUP) startups += 1;
    }
    try testing.expectEqual(@as(usize, 1), startups);
}

test "each fixed step runs the fixed pre-update, update and post-update phases in that order" {
    var r = InlineRuntime{};
    try r.init();

    var seen_log = PhaseLog{};
    const phases = [_]c_int{ abi_runtime.KE_PHASE_FIXED_POST_UPDATE, abi_runtime.KE_PHASE_FIXED_UPDATE, abi_runtime.KE_PHASE_FIXED_PRE_UPDATE };
    var entries: [phases.len]PhaseLogEntry = undefined;
    for (phases, 0..) |ph, i| {
        entries[i] = .{ .log = &seen_log, .phase = ph };
        var sys = systemParams("Logged", ph);
        sys.execute = &phaseLogBody;
        sys.user_data = &entries[i];
        try testing.expect(systemId(r.rt(), &sys) != 0);
    }

    try testing.expect(ticked(r.rt(), 2.0 / 60.0));
    r.bare.deinit();

    const step = [_]c_int{ abi_runtime.KE_PHASE_FIXED_PRE_UPDATE, abi_runtime.KE_PHASE_FIXED_UPDATE, abi_runtime.KE_PHASE_FIXED_POST_UPDATE };
    try testing.expectEqualSlices(c_int, &(step ++ step), seen_log.seen[0..seen_log.count]);
}

test "the shutdown phase runs once when the runtime is destroyed, after every tick" {
    var r = InlineRuntime{};
    try r.init();

    var seen_log = PhaseLog{};
    const phases = [_]c_int{ abi_runtime.KE_PHASE_SHUTDOWN, abi_runtime.KE_PHASE_UPDATE };
    var entries: [phases.len]PhaseLogEntry = undefined;
    for (phases, 0..) |ph, i| {
        entries[i] = .{ .log = &seen_log, .phase = ph };
        var sys = systemParams("Logged", ph);
        sys.execute = &phaseLogBody;
        sys.user_data = &entries[i];
        try testing.expect(systemId(r.rt(), &sys) != 0);
    }

    for (0..2) |_| try testing.expect(ticked(r.rt(), 0.001));
    try testing.expectEqual(@as(usize, 2), seen_log.count);
    r.bare.deinit();

    try testing.expectEqual(@as(usize, 3), seen_log.count);
    try testing.expectEqual(@as(c_int, abi_runtime.KE_PHASE_SHUTDOWN), seen_log.seen[2]);
}

fn fakeQueryRegister(_: ?*abi_ecs.ke_ecs, _: [*c]const abi_ecs.ke_component_id, _: usize, out_query: [*c]abi_ecs.ke_query_id) callconv(.c) abi_result.ke_result {
    out_query.* = 1;
    return R.ok;
}

const many_segments = 100;
var many_entity: [1]abi_ecs.ke_entity = .{7};
var many_column: [1]u32 = .{9};
var seen_segments: usize = 0;
var seen_entities: usize = 0;

var fake_term_count: usize = 1;

fn fakeQueryResolveMany(_: ?*abi_ecs.ke_ecs, _: abi_ecs.ke_query_id, out: [*c]abi_ecs.ke_ecs_segment, max: usize, out_columns: [*c]?*anyopaque, out_count: [*c]usize) callconv(.c) abi_result.ke_result {
    for (0..@min(max, many_segments)) |i| {
        const cols = out_columns + i * fake_term_count;
        for (0..fake_term_count) |t| cols[t] = &many_column;
        out[i] = std.mem.zeroes(abi_ecs.ke_ecs_segment);
        out[i].count = 1;
        out[i].entities = &many_entity;
        out[i].columns = cols;
        out[i].column_count = @intCast(fake_term_count);
    }
    out_count.* = many_segments;
    return R.ok;
}

fn fakeComponentSize(_: ?*abi_ecs.ke_ecs, _: abi_ecs.ke_component_id) callconv(.c) usize {
    return 4;
}

fn viewBody(ctx: ?*abi_runtime.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    var count: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &count);
    seen_segments = count;
    seen_entities = 0;
    for (0..count) |i| seen_entities += segs.?[i].count;
    return R.ok;
}

fn manySegmentRuntime(r: *InlineRuntime, phase: c_int) !void {
    r.bare.ecs.query_register = @ptrCast(&fakeQueryRegister);
    r.bare.ecs.query_resolve = @ptrCast(&fakeQueryResolveMany);
    r.bare.ecs.component_size = @ptrCast(&fakeComponentSize);
    try r.init();
    const terms = [_]abi_runtime.ke_component_access{access(1, abi_runtime.KE_ACCESS_READ)};
    var sys = systemParams("Fragmented", phase);
    sys.execute = &viewBody;
    withQueries(&sys, &.{queryOf(&terms)});
    try testing.expect(systemId(r.rt(), &sys) != 0);
    seen_segments = 0;
    seen_entities = 0;
}

test "a sim query matching more segments than its buffer starts with is resolved into a bigger one and seen whole" {
    var r = InlineRuntime{};
    try manySegmentRuntime(&r, abi_runtime.KE_PHASE_UPDATE);
    defer r.bare.deinit();

    try testing.expect(ticked(r.rt(), 0.001));
    try testing.expectEqual(@as(usize, many_segments), seen_segments);
    try testing.expectEqual(@as(usize, many_segments), seen_entities);
}

test "a render query matching more segments than the extraction scratch starts with is extracted whole" {
    var r = InlineRuntime{};
    try manySegmentRuntime(&r, abi_runtime.KE_PHASE_RENDER);
    defer r.bare.deinit();

    try testing.expect(ticked(r.rt(), 0.001));
    try testing.expectEqual(@as(usize, 1), seen_segments);
    try testing.expectEqual(@as(usize, many_segments), seen_entities);
}

test "an unregistered system no longer runs and the others keep running" {
    var r = InlineRuntime{};
    try r.init();
    defer r.bare.deinit();

    var seen_log = PhaseLog{};
    var entries: [3]PhaseLogEntry = undefined;
    var ids: [3]abi_runtime.ke_system_id = undefined;
    const phases = [_]c_int{ abi_runtime.KE_PHASE_PRE_UPDATE, abi_runtime.KE_PHASE_UPDATE, abi_runtime.KE_PHASE_POST_UPDATE };
    for (phases, 0..) |ph, i| {
        entries[i] = .{ .log = &seen_log, .phase = ph };
        var sys = systemParams("Logged", ph);
        sys.execute = &phaseLogBody;
        sys.user_data = &entries[i];
        ids[i] = systemId(r.rt(), &sys);
        try testing.expect(ids[i] != 0);
    }

    try testing.expectEqual(ids[2], r.rt().last_system.?(r.rt()));
    try testing.expect(r.rt().unregister_system.?(r.rt(), ids[1]) == R.ok);
    try testing.expectEqual(ids[2], r.rt().last_system.?(r.rt()));
    try testing.expectError(error.NotFound, R.check(r.rt().unregister_system.?(r.rt(), ids[1])));

    try testing.expect(ticked(r.rt(), 0.001));
    try testing.expectEqual(@as(usize, 2), seen_log.count);
    try testing.expectEqual(@as(c_int, abi_runtime.KE_PHASE_PRE_UPDATE), seen_log.seen[0]);
    try testing.expectEqual(@as(c_int, abi_runtime.KE_PHASE_POST_UPDATE), seen_log.seen[1]);
}

const MidTick = struct {
    rt: *abi_runtime.ke_runtime,
    registered: bool = false,
    late_runs: u32 = 0,
    unregister_accepted: bool = false,
    keep: bool = false,
    late_id: abi_runtime.ke_system_id = 0,
};

fn lateBody(_: ?*abi_runtime.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const m: *MidTick = @ptrCast(@alignCast(ud.?));
    m.late_runs += 1;
    return R.ok;
}

fn registeringBody(_: ?*abi_runtime.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const m: *MidTick = @ptrCast(@alignCast(ud.?));
    if (m.registered) return R.ok;
    m.registered = true;
    var late = systemParams("Late", abi_runtime.KE_PHASE_UPDATE);
    late.execute = &lateBody;
    late.user_data = m;
    m.late_id = systemId(m.rt, &late);
    if (!m.keep) m.unregister_accepted = (m.rt.unregister_system.?(m.rt, m.late_id) == R.ok);
    return R.ok;
}

test "a system registered and unregistered by the same body never runs" {
    var r = InlineRuntime{};
    try r.init();
    defer r.bare.deinit();

    var m = MidTick{ .rt = r.rt() };
    var first = systemParams("Registers", abi_runtime.KE_PHASE_UPDATE);
    first.execute = &registeringBody;
    first.user_data = &m;
    try testing.expect(systemId(r.rt(), &first) != 0);

    try testing.expect(ticked(r.rt(), 0.001));
    try testing.expect(m.late_id != 0);
    try testing.expect(m.unregister_accepted);

    try testing.expect(ticked(r.rt(), 0.001));
    try testing.expect(ticked(r.rt(), 0.001));
    try testing.expectEqual(@as(u32, 0), m.late_runs);
}

test "a system registered from a body mid-tick starts running on the next tick" {
    var r = InlineRuntime{};
    try r.init();
    defer r.bare.deinit();

    var m = MidTick{ .rt = r.rt(), .keep = true };
    var first = systemParams("Registers", abi_runtime.KE_PHASE_UPDATE);
    first.execute = &registeringBody;
    first.user_data = &m;
    try testing.expect(systemId(r.rt(), &first) != 0);

    try testing.expect(ticked(r.rt(), 0.001));
    try testing.expect(m.late_id != 0);
    try testing.expectEqual(@as(u32, 0), m.late_runs);

    try testing.expect(ticked(r.rt(), 0.001));
    try testing.expectEqual(@as(u32, 1), m.late_runs);
    try testing.expectEqual(m.late_id, r.rt().last_system.?(r.rt()));
}

fn unregisteringBody(_: ?*abi_runtime.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const m: *MidTick = @ptrCast(@alignCast(ud.?));
    if (m.registered) return R.ok;
    m.registered = true;
    m.unregister_accepted = (m.rt.unregister_system.?(m.rt, m.late_id) == R.ok);
    return R.ok;
}

test "a system unregistered from a body stops running from the next tick, and its removal is not lost" {
    var r = InlineRuntime{};
    try r.init();
    defer r.bare.deinit();

    var m = MidTick{ .rt = r.rt() };
    var late = systemParams("Doomed", abi_runtime.KE_PHASE_PRE_UPDATE);
    late.execute = &lateBody;
    late.user_data = &m;
    m.late_id = systemId(r.rt(), &late);
    var killer = systemParams("Killer", abi_runtime.KE_PHASE_UPDATE);
    killer.execute = &unregisteringBody;
    killer.user_data = &m;
    try testing.expect(systemId(r.rt(), &killer) != 0);

    try testing.expect(ticked(r.rt(), 0.001));
    try testing.expectEqual(@as(u32, 1), m.late_runs);
    try testing.expect(m.unregister_accepted);

    try testing.expect(ticked(r.rt(), 0.001));
    try testing.expectEqual(@as(u32, 1), m.late_runs);
}

fn renderRegisteringBody(_: ?*abi_runtime.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const m: *MidTick = @ptrCast(@alignCast(ud.?));
    if (m.registered) return R.ok;
    m.registered = true;
    var late = systemParams("LateFromRender", abi_runtime.KE_PHASE_UPDATE);
    late.execute = &lateBody;
    late.user_data = m;
    m.late_id = systemId(m.rt, &late);
    return R.ok;
}

test "a system registered from a render body is queued instead of waiting on the render phase it runs in" {
    var r = InlineRuntime{};
    try r.init();
    defer r.bare.deinit();

    var m = MidTick{ .rt = r.rt() };
    var first = systemParams("RenderRegisters", abi_runtime.KE_PHASE_RENDER);
    first.execute = &renderRegisteringBody;
    first.user_data = &m;
    try testing.expect(systemId(r.rt(), &first) != 0);

    try testing.expect(ticked(r.rt(), 0.001));
    try testing.expect(m.late_id != 0);
    try testing.expectEqual(@as(u32, 0), m.late_runs);

    try testing.expect(ticked(r.rt(), 0.001));
    try testing.expectEqual(@as(u32, 1), m.late_runs);
}

test "creating a runtime without an ecs is refused" {
    var f = try Fixture.init();
    defer f.deinit();

    var rp = std.mem.zeroes(abi_runtime_factory.ke_runtime_params);
    const rh = createdRuntime(null, f.scheduler_h.ref, &rp);
    try testing.expect(rh.ref == null);
}

test "creating a runtime without a scheduler is refused" {
    var f = try Fixture.init();
    defer f.deinit();

    var rp = std.mem.zeroes(abi_runtime_factory.ke_runtime_params);
    const rh = createdRuntime(f.ecs_h.ref, null, &rp);
    try testing.expect(rh.ref == null);
}

const ParallelProbe = struct {
    arrived: Counter = Counter.init(0),
    tids: [2]std.atomic.Value(u64) = .{ std.atomic.Value(u64).init(0), std.atomic.Value(u64).init(0) },
    distinct: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    total: Counter = Counter.init(0),
};

const ParallelSlot = struct {
    probe: *ParallelProbe,
    index: usize,
};

const parallel_rendezvous_spin_cap: u32 = 4_000_000;

fn parallelWorker(_: ?*abi_runtime.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const slot: *ParallelSlot = @ptrCast(@alignCast(ud.?));
    const p = slot.probe;

    p.tids[slot.index].store(@intCast(std.Thread.getCurrentId()), .release);
    _ = p.arrived.fetchAdd(1, .acq_rel);

    var spins: u32 = 0;
    while (p.arrived.load(.acquire) % 2 != 0 and spins < parallel_rendezvous_spin_cap) : (spins += 1) {
        std.atomic.spinLoopHint();
    }

    const a = p.tids[0].load(.acquire);
    const b = p.tids[1].load(.acquire);
    if (a != 0 and b != 0 and a != b) p.distinct.store(true, .release);

    _ = p.total.fetchAdd(1, .acq_rel);
    return R.ok;
}

test "disjoint systems in one wave run on more than one thread" {
    var f = try Fixture.init();
    defer f.deinit();

    var probe = ParallelProbe{};
    var slot_a = ParallelSlot{ .probe = &probe, .index = 0 };
    var slot_b = ParallelSlot{ .probe = &probe, .index = 1 };

    const acc_a = [_]abi_runtime.ke_component_access{access(1, abi_runtime.KE_ACCESS_WRITE)};
    const acc_b = [_]abi_runtime.ke_component_access{access(2, abi_runtime.KE_ACCESS_WRITE)};

    var sa = systemParams("SysA", abi_runtime.KE_PHASE_UPDATE);
    sa.access_list = &acc_a;
    sa.access_count = 1;
    sa.user_data = &slot_a;
    sa.execute = &parallelWorker;
    try testing.expect(systemId(f.rt(), &sa) != 0);

    var sb = systemParams("SysB", abi_runtime.KE_PHASE_UPDATE);
    sb.access_list = &acc_b;
    sb.access_count = 1;
    sb.user_data = &slot_b;
    sb.execute = &parallelWorker;
    try testing.expect(systemId(f.rt(), &sb) != 0);

    for (0..20) |_| try testing.expect(f.tick(1.0 / 60.0));

    try testing.expectEqual(@as(u32, 40), probe.total.load(.acquire));
    try testing.expect(probe.distinct.load(.acquire));
}

const OrderProbe = struct {
    slots: [8]Counter = @splat(Counter.init(0)),
    next: Counter = Counter.init(0),
};

const OrderSlot = struct {
    probe: *OrderProbe,
    tag: u32,
};

fn orderWorker(_: ?*abi_runtime.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const slot: *OrderSlot = @ptrCast(@alignCast(ud.?));
    const i = slot.probe.next.fetchAdd(1, .acq_rel);
    if (i < slot.probe.slots.len) slot.probe.slots[i].store(slot.tag, .release);
    return R.ok;
}

test "systems conflicting on a component run one after the other" {
    var f = try Fixture.init();
    defer f.deinit();

    var probe = OrderProbe{};
    var slot_1 = OrderSlot{ .probe = &probe, .tag = 1 };
    var slot_2 = OrderSlot{ .probe = &probe, .tag = 2 };

    const acc = [_]abi_runtime.ke_component_access{access(42, abi_runtime.KE_ACCESS_WRITE)};

    var s1 = systemParams("Writer1", abi_runtime.KE_PHASE_UPDATE);
    s1.access_list = &acc;
    s1.access_count = 1;
    s1.user_data = &slot_1;
    s1.execute = &orderWorker;
    try testing.expect(systemId(f.rt(), &s1) != 0);

    var s2 = systemParams("Writer2", abi_runtime.KE_PHASE_UPDATE);
    s2.access_list = &acc;
    s2.access_count = 1;
    s2.user_data = &slot_2;
    s2.execute = &orderWorker;
    try testing.expect(systemId(f.rt(), &s2) != 0);

    try testing.expect(f.tick(1.0 / 60.0));

    try testing.expectEqual(@as(u32, 2), probe.next.load(.acquire));
    try testing.expectEqual(@as(u32, 1), probe.slots[0].load(.acquire));
    try testing.expectEqual(@as(u32, 2), probe.slots[1].load(.acquire));
}

test "the fixed phase accumulates at its own rate" {
    var f = try Fixture.init();
    defer f.deinit();

    var fixed_ticks = Counter.init(0);
    var update_ticks = Counter.init(0);

    var fx = systemParams("FixedCounter", abi_runtime.KE_PHASE_FIXED_UPDATE);
    fx.user_data = &fixed_ticks;
    fx.execute = &countingSystem;
    try testing.expect(systemId(f.rt(), &fx) != 0);

    var up = systemParams("UpdateCounter", abi_runtime.KE_PHASE_UPDATE);
    up.user_data = &update_ticks;
    up.execute = &countingSystem;
    try testing.expect(systemId(f.rt(), &up) != 0);

    for (0..10) |_| try testing.expect(f.tick(1.0 / 60.0));

    try testing.expectEqual(@as(u32, 10), update_ticks.load(.acquire));
    try testing.expectEqual(@as(u32, 10), fixed_ticks.load(.acquire));
}

test "a large frame catches the fixed phase up" {
    var f = try Fixture.init();
    defer f.deinit();

    var fixed_ticks = Counter.init(0);
    var fx = systemParams("FixedCounter", abi_runtime.KE_PHASE_FIXED_UPDATE);
    fx.user_data = &fixed_ticks;
    fx.execute = &countingSystem;
    try testing.expect(systemId(f.rt(), &fx) != 0);

    try testing.expect(f.tick(5.0 / 60.0));
    try testing.expectEqual(@as(u32, 5), fixed_ticks.load(.acquire));
}

test "a frame shorter than the fixed step takes no step" {
    var f = try Fixture.init();
    defer f.deinit();

    var fixed_ticks = Counter.init(0);
    var fx = systemParams("FixedCounter", abi_runtime.KE_PHASE_FIXED_UPDATE);
    fx.user_data = &fixed_ticks;
    fx.execute = &countingSystem;
    try testing.expect(systemId(f.rt(), &fx) != 0);

    try testing.expect(f.tick(1.0 / 120.0));
    try testing.expectEqual(@as(u32, 0), fixed_ticks.load(.acquire));

    try testing.expect(f.tick(1.0 / 120.0));
    try testing.expectEqual(@as(u32, 1), fixed_ticks.load(.acquire));
}

test "a huge frame is capped so the fixed phase cannot spiral" {
    var f = try Fixture.init();
    defer f.deinit();

    var fixed_ticks = Counter.init(0);
    var fx = systemParams("FixedCounter", abi_runtime.KE_PHASE_FIXED_UPDATE);
    fx.user_data = &fixed_ticks;
    fx.execute = &countingSystem;
    try testing.expect(systemId(f.rt(), &fx) != 0);

    try testing.expect(f.tick(1.0));

    const steps = fixed_ticks.load(.acquire);
    try testing.expect(steps <= 15);
    try testing.expect(steps >= 14);
}

test "a negative delta time is refused" {
    var f = try Fixture.init();
    defer f.deinit();

    try testing.expect(!f.tick(-1.0));
}

var g_gated_render_runs = Counter.init(0);
var g_gated_render_may_finish = std.atomic.Value(bool).init(false);

fn gatedRenderBody(_: ?*abi_runtime.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    while (!g_gated_render_may_finish.load(.acquire)) std.atomic.spinLoopHint();
    _ = g_gated_render_runs.fetchAdd(1, .acq_rel);
    return R.ok;
}

test "tick dispatches the render phase without waiting for it" {
    var f = try Fixture.init();
    defer f.deinit();

    g_gated_render_runs.store(0, .release);
    g_gated_render_may_finish.store(false, .release);

    var rnd = systemParams("GatedRender", abi_runtime.KE_PHASE_RENDER);
    rnd.execute = &gatedRenderBody;
    try testing.expect(systemId(f.rt(), &rnd) != 0);

    try testing.expect(f.tick(1.0 / 60.0));
    try testing.expectEqual(@as(u32, 0), g_gated_render_runs.load(.acquire));

    g_gated_render_may_finish.store(true, .release);
    try testing.expect(f.tick(1.0 / 60.0));
    try testing.expect(g_gated_render_runs.load(.acquire) >= 1);

    f.flushRender();
}

const ExtractProbe = struct {
    seen: std.atomic.Value(i32) = std.atomic.Value(i32).init(-1),
    seen_ptr: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    runs: Counter = Counter.init(0),
};

var g_extract_probe = ExtractProbe{};

fn extractSimWriter(ctx: ?*abi_runtime.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    var seg_count: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &seg_count);
    if (segs == null) return R.ok;
    for (0..seg_count) |s| {
        const col: [*]i32 = @ptrCast(@alignCast(segs.?[s].columns.?[0] orelse continue));
        for (0..segs.?[s].count) |i| col[i] = 42;
    }
    return R.ok;
}

fn extractRenderReader(ctx: ?*abi_runtime.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    var seg_count: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &seg_count);
    if (segs != null and seg_count > 0 and segs.?[0].count > 0) {
        if (segs.?[0].columns.?[0]) |col| {
            const typed: [*]const i32 = @ptrCast(@alignCast(col));
            g_extract_probe.seen.store(typed[0], .release);
            g_extract_probe.seen_ptr.store(@intFromPtr(col), .release);
        }
    }
    _ = g_extract_probe.runs.fetchAdd(1, .acq_rel);
    return R.ok;
}

test "the render extract carries this tick's sim write" {
    var f = try Fixture.init();
    defer f.deinit();

    var cid: abi_ecs.ke_component_id = 0;
    try R.check(f.ecs().component_register.?(f.ecs(), &abi_ecs.ke_component_params{ .name = "Extract.Value", .size = @sizeOf(i32), .alignment = @alignOf(i32), .fields = null, .field_count = 0 }, &cid));
    const e = try ecsSpawn(f.ecs());
    const v = (try ecsAttach(f.ecs(), e, cid));
    try testing.expect(v != null);
    @as(*i32, @ptrCast(@alignCast(v.?))).* = 0;

    g_extract_probe.seen.store(-1, .release);
    g_extract_probe.seen_ptr.store(0, .release);
    g_extract_probe.runs.store(0, .release);

    const wterms = [_]abi_runtime.ke_component_access{access(cid, abi_runtime.KE_ACCESS_WRITE)};

    var sim = systemParams("SimWriter", abi_runtime.KE_PHASE_UPDATE);
    withQueries(&sim, &.{queryOf(&wterms)});
    sim.execute = &extractSimWriter;
    try testing.expect(systemId(f.rt(), &sim) != 0);

    const rterms = [_]abi_runtime.ke_component_access{access(cid, abi_runtime.KE_ACCESS_READ)};

    var rnd = systemParams("RenderReader", abi_runtime.KE_PHASE_RENDER);
    withQueries(&rnd, &.{queryOf(&rterms)});
    rnd.execute = &extractRenderReader;
    try testing.expect(systemId(f.rt(), &rnd) != 0);

    try testing.expect(f.tick(1.0 / 60.0));
    f.flushRender();

    try testing.expect(g_extract_probe.runs.load(.acquire) >= 1);
    try testing.expectEqual(@as(i32, 42), g_extract_probe.seen.load(.acquire));

    const live_ptr = @intFromPtr(f.ecs().component_get.?(f.ecs(), e, cid));
    try testing.expect(g_extract_probe.seen_ptr.load(.acquire) != live_ptr);
}

const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

var g_extract_pv_sum: f64 = 0.0;
var g_extract_pv_runs = Counter.init(0);

fn extractPosVelReader(ctx: ?*abi_runtime.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    var seg_count: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &seg_count);
    if (segs != null) {
        for (0..seg_count) |s| {
            const pc: [*]const Vec3 = @ptrCast(@alignCast(segs.?[s].columns.?[0] orelse continue));
            const vc: [*]const Vec3 = @ptrCast(@alignCast(segs.?[s].columns.?[1] orelse continue));
            for (0..segs.?[s].count) |i| {
                g_extract_pv_sum += @as(f64, pc[i].x) + @as(f64, vc[i].x);
            }
        }
    }
    _ = g_extract_pv_runs.fetchAdd(1, .acq_rel);
    return R.ok;
}

test "the render extract keeps multi term columns aligned" {
    var f = try Fixture.init();
    defer f.deinit();

    var pos: abi_ecs.ke_component_id = 0;
    try R.check(f.ecs().component_register.?(f.ecs(), &abi_ecs.ke_component_params{ .name = "ExtractPos", .size = @sizeOf(Vec3), .alignment = @alignOf(Vec3), .fields = null, .field_count = 0 }, &pos));
    var vel: abi_ecs.ke_component_id = 0;
    try R.check(f.ecs().component_register.?(f.ecs(), &abi_ecs.ke_component_params{ .name = "ExtractVel", .size = @sizeOf(Vec3), .alignment = @alignOf(Vec3), .fields = null, .field_count = 0 }, &vel));

    var expect: f64 = 0.0;
    for (0..64) |i| {
        const e = try ecsSpawn(f.ecs());
        _ = (try ecsAttach(f.ecs(), e, pos));
        _ = (try ecsAttach(f.ecs(), e, vel));
        const p: *Vec3 = @ptrCast(@alignCast(f.ecs().component_get.?(f.ecs(), e, pos).?));
        const v: *Vec3 = @ptrCast(@alignCast(f.ecs().component_get.?(f.ecs(), e, vel).?));
        p.x = @floatFromInt(i);
        v.x = @floatFromInt(i * 2);
        expect += @as(f64, @floatFromInt(i)) + @as(f64, @floatFromInt(i * 2));
    }

    const rterms = [_]abi_runtime.ke_component_access{ access(pos, abi_runtime.KE_ACCESS_READ), access(vel, abi_runtime.KE_ACCESS_READ) };

    var rnd = systemParams("RenderPosVel", abi_runtime.KE_PHASE_RENDER);
    withQueries(&rnd, &.{queryOf(&rterms)});
    rnd.execute = &extractPosVelReader;
    try testing.expect(systemId(f.rt(), &rnd) != 0);

    g_extract_pv_sum = 0.0;
    g_extract_pv_runs.store(0, .release);

    try testing.expect(f.tick(1.0 / 60.0));
    f.flushRender();

    try testing.expect(g_extract_pv_runs.load(.acquire) >= 1);
    try testing.expectEqual(expect, g_extract_pv_sum);
}

fn waveSystem(name: [*c]const u8, list: []const abi_runtime.ke_component_access) abi_runtime.ke_runtime_system_params {
    var s = systemParams(name, abi_runtime.KE_PHASE_UPDATE);
    s.access_list = list.ptr;
    s.access_count = @intCast(list.len);
    s.execute = &noopSystem;
    return s;
}

fn orderOf(params: []const abi_runtime.ke_runtime_system_params, rules: wave_mod.Rules, waves: []u32) wave_mod.Order {
    var nodes: [8]wave_mod.Node = undefined;
    for (params, nodes[0..params.len]) |*p, *n| n.* = .{ .params = p, .explicit = if (p.access_list != null) p.access_list.?[0..p.access_count] else &.{} };
    return wave_mod.order(nodes[0..params.len], rules, waves);
}

test "no systems produce no waves" {
    var waves: [1]u32 = undefined;
    try testing.expectEqual(@as(u32, 0), orderOf(&.{}, .{}, &waves).wave_count);
}

test "systems writing different components share a wave" {
    const a = [_]abi_runtime.ke_component_access{access(1, abi_runtime.KE_ACCESS_WRITE)};
    const b = [_]abi_runtime.ke_component_access{access(2, abi_runtime.KE_ACCESS_WRITE)};
    const sys = [_]abi_runtime.ke_runtime_system_params{ waveSystem("a", &a), waveSystem("b", &b) };
    var waves: [2]u32 = undefined;
    const o = orderOf(&sys, .{}, &waves);

    try testing.expectEqual(@as(u32, 1), o.wave_count);
    try testing.expectEqual(wave_mod.Problem.none, o.ambiguity);
}

test "a writer runs before a reader of what it writes, whichever registered first" {
    const reader = [_]abi_runtime.ke_component_access{access(5, abi_runtime.KE_ACCESS_READ)};
    const writer = [_]abi_runtime.ke_component_access{access(5, abi_runtime.KE_ACCESS_WRITE)};
    const sys = [_]abi_runtime.ke_runtime_system_params{ waveSystem("reader", &reader), waveSystem("writer", &writer) };
    var waves: [2]u32 = undefined;
    const o = orderOf(&sys, .{}, &waves);

    try testing.expectEqual(@as(u32, 2), o.wave_count);
    try testing.expectEqual(@as(u32, 1), waves[0]);
    try testing.expectEqual(@as(u32, 0), waves[1]);
}

test "two readers of the same component share a wave" {
    const a = [_]abi_runtime.ke_component_access{access(7, abi_runtime.KE_ACCESS_READ)};
    const sys = [_]abi_runtime.ke_runtime_system_params{ waveSystem("a", &a), waveSystem("b", &a) };
    var waves: [2]u32 = undefined;

    try testing.expectEqual(@as(u32, 1), orderOf(&sys, .{}, &waves).wave_count);
}

test "two writers with no order run in registration order and are reported as ambiguous" {
    const a = [_]abi_runtime.ke_component_access{access(1, abi_runtime.KE_ACCESS_WRITE)};
    const sys = [_]abi_runtime.ke_runtime_system_params{ waveSystem("first", &a), waveSystem("second", &a) };
    var waves: [2]u32 = undefined;
    const o = orderOf(&sys, .{}, &waves);

    try testing.expectEqual(@as(u32, 0), waves[0]);
    try testing.expectEqual(@as(u32, 1), waves[1]);
    try testing.expectEqualStrings("first", std.mem.span(o.ambiguity.ambiguity.first));
    try testing.expectEqualStrings("second", std.mem.span(o.ambiguity.ambiguity.second));
    try testing.expectEqual(wave_mod.Problem.none, o.failure);
}

test "a system named in after runs first, against registration order and without ambiguity" {
    const a = [_]abi_runtime.ke_component_access{access(1, abi_runtime.KE_ACCESS_WRITE)};
    const after = [_][*c]const u8{"late"};
    var first = waveSystem("first", &a);
    first.after = &after;
    first.after_count = 1;
    const sys = [_]abi_runtime.ke_runtime_system_params{ first, waveSystem("late", &a) };
    var waves: [2]u32 = undefined;
    const o = orderOf(&sys, .{}, &waves);

    try testing.expectEqual(@as(u32, 1), waves[0]);
    try testing.expectEqual(@as(u32, 0), waves[1]);
    try testing.expectEqual(wave_mod.Problem.none, o.ambiguity);
}

test "a system naming another in before runs first" {
    const a = [_]abi_runtime.ke_component_access{access(1, abi_runtime.KE_ACCESS_WRITE)};
    const before = [_][*c]const u8{"first"};
    var late = waveSystem("late", &a);
    late.before = &before;
    late.before_count = 1;
    const sys = [_]abi_runtime.ke_runtime_system_params{ waveSystem("first", &a), late };
    var waves: [2]u32 = undefined;
    _ = orderOf(&sys, .{}, &waves);

    try testing.expectEqual(@as(u32, 1), waves[0]);
    try testing.expectEqual(@as(u32, 0), waves[1]);
}

test "an after naming no system of the phase fails the order" {
    const a = [_]abi_runtime.ke_component_access{access(1, abi_runtime.KE_ACCESS_WRITE)};
    const after = [_][*c]const u8{"missing"};
    var s = waveSystem("lonely", &a);
    s.after = &after;
    s.after_count = 1;
    var waves: [1]u32 = undefined;
    const o = orderOf(&.{s}, .{}, &waves);

    try testing.expectEqualStrings("missing", std.mem.span(o.failure.unknown_name.name));
}

test "two systems each after the other fail the order as a cycle" {
    const a = [_]abi_runtime.ke_component_access{access(1, abi_runtime.KE_ACCESS_READ)};
    const after_b = [_][*c]const u8{"b"};
    const after_a = [_][*c]const u8{"a"};
    var sa = waveSystem("a", &a);
    sa.after = &after_b;
    sa.after_count = 1;
    var sb = waveSystem("b", &a);
    sb.after = &after_a;
    sb.after_count = 1;
    var waves: [2]u32 = undefined;
    const o = orderOf(&.{ sa, sb }, .{}, &waves);

    try testing.expect(o.failure == .cycle);
}

test "writers of a component its owner orders share a wave and are not ambiguous" {
    const a = [_]abi_runtime.ke_component_access{access(9, abi_runtime.KE_ACCESS_WRITE)};
    const r = [_]abi_runtime.ke_component_access{access(9, abi_runtime.KE_ACCESS_READ)};
    const sys = [_]abi_runtime.ke_runtime_system_params{ waveSystem("p1", &a), waveSystem("p2", &a), waveSystem("end", &r) };
    const owned = [_]abi_ecs.ke_component_id{9};
    var waves: [3]u32 = undefined;
    const o = orderOf(&sys, .{ .self_ordered = &owned }, &waves);

    try testing.expectEqual(@as(u32, 2), o.wave_count);
    try testing.expectEqual(waves[0], waves[1]);
    try testing.expectEqual(@as(u32, 1), waves[2]);
    try testing.expectEqual(wave_mod.Problem.none, o.ambiguity);
}

test "systems whose queries require different members of an exclusive group share a wave" {
    const body = access(3, abi_runtime.KE_ACCESS_WRITE);
    const ball_terms = [_]abi_runtime.ke_component_access{ body, access(10, abi_runtime.KE_ACCESS_READ) };
    const paddle_terms = [_]abi_runtime.ke_component_access{ body, access(11, abi_runtime.KE_ACCESS_READ) };
    const ball_q = [_]queries_mod.QueryDecl{.{ .terms = &ball_terms, .term_count = 2 }};
    const paddle_q = [_]queries_mod.QueryDecl{.{ .terms = &paddle_terms, .term_count = 2 }};
    const ball = waveSystem("ball", &ball_terms);
    const paddle = waveSystem("paddle", &paddle_terms);
    const nodes = [_]wave_mod.Node{ .{ .params = &ball, .queries = &ball_q }, .{ .params = &paddle, .queries = &paddle_q } };
    const members = [_]wave_mod.Exclusive{ .{ .group = 20, .member = 10 }, .{ .group = 20, .member = 11 } };
    var waves: [2]u32 = undefined;
    const o = wave_mod.order(&nodes, .{ .exclusive = &members }, &waves);

    try testing.expectEqual(@as(u32, 1), o.wave_count);
    try testing.expectEqual(wave_mod.Problem.none, o.ambiguity);
}

test "what an access list names still orders systems confined to different members" {
    const ball_terms = [_]abi_runtime.ke_component_access{ access(3, abi_runtime.KE_ACCESS_WRITE), access(10, abi_runtime.KE_ACCESS_READ) };
    const paddle_terms = [_]abi_runtime.ke_component_access{ access(3, abi_runtime.KE_ACCESS_WRITE), access(11, abi_runtime.KE_ACCESS_READ) };
    const shared = [_]abi_runtime.ke_component_access{access(3, abi_runtime.KE_ACCESS_WRITE)};
    const ball_q = [_]queries_mod.QueryDecl{.{ .terms = &ball_terms, .term_count = 2 }};
    const paddle_q = [_]queries_mod.QueryDecl{.{ .terms = &paddle_terms, .term_count = 2 }};
    const ball = waveSystem("ball", &ball_terms);
    const paddle = waveSystem("paddle", &paddle_terms);
    const nodes = [_]wave_mod.Node{ .{ .params = &ball, .queries = &ball_q, .explicit = &shared }, .{ .params = &paddle, .queries = &paddle_q } };
    const members = [_]wave_mod.Exclusive{ .{ .group = 20, .member = 10 }, .{ .group = 20, .member = 11 } };
    var waves: [2]u32 = undefined;

    try testing.expectEqual(@as(u32, 2), wave_mod.order(&nodes, .{ .exclusive = &members }, &waves).wave_count);
}

test "independent chains of writers and readers run side by side" {
    const a = [_]abi_runtime.ke_component_access{access(1, abi_runtime.KE_ACCESS_WRITE)};
    const b = [_]abi_runtime.ke_component_access{access(1, abi_runtime.KE_ACCESS_READ)};
    const d = [_]abi_runtime.ke_component_access{access(2, abi_runtime.KE_ACCESS_WRITE)};
    const e = [_]abi_runtime.ke_component_access{access(2, abi_runtime.KE_ACCESS_READ)};
    const sys = [_]abi_runtime.ke_runtime_system_params{ waveSystem("a", &a), waveSystem("b", &b), waveSystem("d", &d), waveSystem("e", &e) };
    var waves: [4]u32 = undefined;

    try testing.expectEqual(@as(u32, 2), orderOf(&sys, .{}, &waves).wave_count);
    try testing.expectEqual(waves[0], waves[2]);
    try testing.expectEqual(waves[1], waves[3]);
}

test "an exclusive system runs alone before the systems of its phase, whatever it declares" {
    const r = [_]abi_runtime.ke_component_access{access(1, abi_runtime.KE_ACCESS_READ)};
    const w = [_]abi_runtime.ke_component_access{access(2, abi_runtime.KE_ACCESS_WRITE)};
    var flush = waveSystem("flush", &.{});
    flush.exclusive = true;
    const sys = [_]abi_runtime.ke_runtime_system_params{ waveSystem("reader", &r), waveSystem("writer", &w), flush };
    var waves: [3]u32 = undefined;
    const o = orderOf(&sys, .{}, &waves);

    try testing.expectEqual(@as(u32, 0), waves[2]);
    try testing.expectEqual(@as(u32, 1), waves[0]);
    try testing.expectEqual(@as(u32, 1), waves[1]);
    try testing.expectEqual(wave_mod.Problem.none, o.ambiguity);
}

test "check_order reports two unordered writers only when asked to refuse them" {
    var fx = try Fixture.init();
    defer fx.deinit();
    const rt = fx.rt();
    const a = [_]abi_runtime.ke_component_access{access(1, abi_runtime.KE_ACCESS_WRITE)};
    var p = waveSystem("first", &a);
    try testing.expect(systemId(rt, &p) != 0);
    p.name = "second";
    try testing.expect(systemId(rt, &p) != 0);

    try testing.expect(rt.check_order.?(rt, false) == R.ok);
    try testing.expect(!(rt.check_order.?(rt, true) == R.ok));
}

const SpawnProbe = struct {
    ids: [3]abi_ecs.ke_entity = .{ abi_ecs.KE_ENTITY_INVALID, abi_ecs.KE_ENTITY_INVALID, abi_ecs.KE_ENTITY_INVALID },
    calls: Counter = Counter.init(0),
    cid: abi_ecs.ke_component_id = 0,
};

fn spawnerBody(ctx: ?*abi_runtime.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const probe: *SpawnProbe = @ptrCast(@alignCast(ud.?));
    const cmds = ctx.?.commands;
    for (&probe.ids) |*slot| slot.* = spawned(cmds);
    _ = probe.calls.fetchAdd(1, .acq_rel);
    return R.ok;
}

test "a deferred spawn is applied at the wave barrier" {
    var f = try Fixture.init();
    defer f.deinit();

    resetDeferApplied();

    var probe = SpawnProbe{};
    var sys = systemParams("Spawner", abi_runtime.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &spawnerBody;
    try testing.expect(systemId(f.rt(), &sys) != 0);

    try testing.expect(f.tick(1.0 / 60.0));
    try testing.expectEqual(@as(u32, 1), probe.calls.load(.acquire));
    try testing.expectEqual(@as(u32, 3), deferAppliedCount());
}

test "spawn hands the system body an id it can actually use" {
    var f = try Fixture.init();
    defer f.deinit();

    var probe = SpawnProbe{};
    var sys = systemParams("Spawner", abi_runtime.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &spawnerBody;
    try testing.expect(systemId(f.rt(), &sys) != 0);
    try testing.expect(f.tick(1.0 / 60.0));

    const e = f.ecs();
    var cid: abi_ecs.ke_component_id = 0;
    try R.check(e.component_register.?(e, &abi_ecs.ke_component_params{ .name = "spawned_probe", .size = 4, .alignment = 0, .fields = null, .field_count = 0 }, &cid));
    for (probe.ids, 0..) |id, i| {
        try testing.expect(id != abi_ecs.KE_ENTITY_INVALID);
        for (probe.ids[i + 1 ..]) |other| try testing.expect(id != other);
        try testing.expect((try ecsAttach(e, id, cid)) != null);
    }
}

test "an entity spawned with no components still exists after the barrier" {
    var f = try Fixture.init();
    defer f.deinit();

    var probe = SpawnProbe{};
    var sys = systemParams("Spawner", abi_runtime.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &spawnerBody;
    try testing.expect(systemId(f.rt(), &sys) != 0);
    try testing.expect(f.tick(1.0 / 60.0));

    const e = f.ecs();
    var cid: abi_ecs.ke_component_id = 0;
    try R.check(e.component_register.?(e, &abi_ecs.ke_component_params{ .name = "exists_probe", .size = 4, .alignment = 0, .fields = null, .field_count = 0 }, &cid));
    try R.check(e.entity_destroy.?(e, probe.ids[0]));
    var revived: ?*anyopaque = null;
    try testing.expectError(error.InvalidArgument, R.check(e.component_add.?(e, probe.ids[0], cid, &revived)));
}

const MutatorProbe = struct {
    payload: u8 = 'X',
    cid: abi_ecs.ke_component_id = 0,
    target: abi_ecs.ke_entity = abi_ecs.KE_ENTITY_INVALID,
    ok: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

fn mutatorBody(ctx: ?*abi_runtime.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const probe: *MutatorProbe = @ptrCast(@alignCast(ud.?));
    const cmds = ctx.?.commands;
    var entity = probe.target;
    const spawned_ok = entity != abi_ecs.KE_ENTITY_INVALID or cmds.?.spawn.?(cmds, &entity) == R.ok;
    const attached = (cmds.?.attach.?(cmds, entity, probe.cid, &probe.payload, 1) == R.ok);
    const detached = (cmds.?.detach.?(cmds, entity, probe.cid) == R.ok);
    const despawned = (cmds.?.despawn.?(cmds, entity) == R.ok);
    probe.ok.store(spawned_ok and attached and detached and despawned, .release);
    return R.ok;
}

test "deferred attach detach and despawn are applied at the barrier" {
    var f = try Fixture.init();
    defer f.deinit();

    resetDeferApplied();

    var probe = MutatorProbe{};
    try R.check(f.ecs().component_register.?(f.ecs(), &abi_ecs.ke_component_params{ .name = "mutator_probe", .size = 1, .alignment = 0, .fields = null, .field_count = 0 }, &probe.cid));
    var sys = systemParams("Mutator", abi_runtime.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &mutatorBody;
    try testing.expect(systemId(f.rt(), &sys) != 0);

    try testing.expect(f.tick(1.0 / 60.0));
    try testing.expect(probe.ok.load(.acquire));
    try testing.expectEqual(@as(u32, 4), deferAppliedCount());
}

test "a recorded attach the ecs refuses fails the tick and names the system" {
    var f = try Fixture.init();
    defer f.deinit();

    resetDeferApplied();

    var probe = MutatorProbe{ .target = 42 };
    try R.check(f.ecs().component_register.?(f.ecs(), &abi_ecs.ke_component_params{ .name = "refused_probe", .size = 1, .alignment = 0, .fields = null, .field_count = 0 }, &probe.cid));
    var sys = systemParams("Refused", abi_runtime.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &mutatorBody;
    try testing.expect(systemId(f.rt(), &sys) != 0);

    try testing.expectError(error.InvalidArgument, R.check(f.rt().tick.?(f.rt(), 1.0 / 60.0)));
    try testing.expectEqual(@as(u32, 0), deferAppliedCount());
}

fn failingCallback(_: ?*abi_ecs.ke_ecs, _: ?*anyopaque) callconv(.c) abi_result.ke_result {
    return R.code(error.NotFound);
}

fn callbackBody(ctx: ?*abi_runtime.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const cmds = ctx.?.commands;
    return cmds.?.@"defer".?(cmds, failingCallback, null, 0);
}

test "a recorded callback that fails fails the tick and is not counted as applied" {
    var f = try Fixture.init();
    defer f.deinit();

    resetDeferApplied();

    var sys = systemParams("FailingCallback", abi_runtime.KE_PHASE_UPDATE);
    sys.execute = &callbackBody;
    try testing.expect(systemId(f.rt(), &sys) != 0);

    try testing.expectError(error.NotFound, R.check(f.rt().tick.?(f.rt(), 1.0 / 60.0)));
    try testing.expectEqual(@as(u32, 0), deferAppliedCount());
}

fn repeatSpawnerBody(ctx: ?*abi_runtime.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const cmds = ctx.?.commands;
    _ = spawned(cmds);
    return R.ok;
}

const RefusalProbe = struct {
    cid: abi_ecs.ke_component_id = 0,
    wrong_size_refused: bool = false,
    wrong_size_error: abi_result.ke_result = R.ok,
    render_refused: bool = false,
    render_error: abi_result.ke_result = R.ok,
};

fn wrongSizeBody(ctx: ?*abi_runtime.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const probe: *RefusalProbe = @ptrCast(@alignCast(ud.?));
    const cmds = ctx.?.commands;
    var payload: [8]u8 = undefined;
    probe.wrong_size_error = cmds.?.attach.?(cmds, 42, probe.cid, &payload, payload.len);
    probe.wrong_size_refused = probe.wrong_size_error != R.ok;
    return R.ok;
}

fn renderBody(ctx: ?*abi_runtime.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const probe: *RefusalProbe = @ptrCast(@alignCast(ud.?));
    const cmds = ctx.?.commands;
    var entity: abi_ecs.ke_entity = abi_ecs.KE_ENTITY_INVALID;
    probe.render_error = cmds.?.spawn.?(cmds, &entity);
    probe.render_refused = entity == abi_ecs.KE_ENTITY_INVALID;
    return R.ok;
}

test "an attach whose payload size differs from the component size is refused with an error" {
    var f = try Fixture.init();
    defer f.deinit();

    resetDeferApplied();

    var probe = RefusalProbe{};
    try R.check(f.ecs().component_register.?(f.ecs(), &abi_ecs.ke_component_params{ .name = "refusal_probe", .size = 1, .alignment = 0, .fields = null, .field_count = 0 }, &probe.cid));
    var sys = systemParams("WrongSize", abi_runtime.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &wrongSizeBody;
    try testing.expect(systemId(f.rt(), &sys) != 0);

    try testing.expect(f.tick(1.0 / 60.0));
    try testing.expect(probe.wrong_size_refused);
    try testing.expectError(error.InvalidArgument, R.check(probe.wrong_size_error));
    try testing.expectEqual(@as(u32, 0), deferAppliedCount());
}

test "the render phase refuses to record a structural change" {
    var f = try Fixture.init();
    defer f.deinit();

    var probe = RefusalProbe{};
    var sys = systemParams("RenderSpawner", abi_runtime.KE_PHASE_RENDER);
    sys.user_data = &probe;
    sys.execute = &renderBody;
    try testing.expect(systemId(f.rt(), &sys) != 0);

    try testing.expect(f.tick(1.0 / 60.0));
    f.flushRender();
    try testing.expect(probe.render_refused);
    try testing.expectError(error.NotSupported, R.check(probe.render_error));
}

test "the defer queue drains between ticks" {
    var f = try Fixture.init();
    defer f.deinit();

    resetDeferApplied();

    var sys = systemParams("RepeatSpawner", abi_runtime.KE_PHASE_UPDATE);
    sys.execute = &repeatSpawnerBody;
    try testing.expect(systemId(f.rt(), &sys) != 0);

    for (0..5) |_| try testing.expect(f.tick(1.0 / 60.0));

    try testing.expectEqual(@as(u32, 5), deferAppliedCount());
}

test "a zero size component registers as a usable tag" {
    var h: abi_ecs.ke_ecs_handle = undefined;
    try R.check(ke_ecs_flecs_create(null, &h));
    defer h.destroy.?(h.ref);

    const ecs: *abi_ecs.ke_ecs = @ptrCast(h.ref);

    var tag: abi_ecs.ke_component_id = 0;
    try R.check(ecs.component_register.?(ecs, &abi_ecs.ke_component_params{ .name = "ZeroSizeTag", .size = 0, .alignment = 0, .fields = null, .field_count = 0 }, &tag));
    try testing.expect(tag != 0);

    const e = try ecsSpawn(ecs);
    _ = (try ecsAttach(ecs, e, tag));

    var q: abi_ecs.ke_query_id = abi_ecs.KE_QUERY_INVALID;
    try R.check(ecs.query_register.?(ecs, (&tag)[0..1], 1, &q));
    try testing.expect(q != abi_ecs.KE_QUERY_INVALID);

    var segs = std.mem.zeroes([8]abi_ecs.ke_ecs_segment);
    var columns: [8]?*anyopaque = undefined;
    var seg_count: usize = 0;
    try R.check(ecs.query_resolve.?(ecs, q, &segs, 8, &columns[0], &seg_count));

    var total: usize = 0;
    for (0..seg_count) |i| total += segs[i].count;
    try testing.expectEqual(@as(usize, 1), total);
}

fn parallelReaderBody(ctx: ?*abi_runtime.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    var seg_count: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &seg_count);
    if (segs == null) return R.ok;

    var sink: f32 = 0.0;
    for (0..seg_count) |s| {
        const col: [*]const Vec3 = @ptrCast(@alignCast(segs.?[s].columns.?[0] orelse continue));
        for (0..segs.?[s].count) |i| sink += col[i].x;
    }
    std.mem.doNotOptimizeAway(sink);
    return R.ok;
}

test "two readers sharing a wave read the same storage without conflicting" {
    var f = try Fixture.init();
    defer f.deinit();

    var pos: abi_ecs.ke_component_id = 0;
    try R.check(f.ecs().component_register.?(f.ecs(), &abi_ecs.ke_component_params{ .name = "pos", .size = @sizeOf(Vec3), .alignment = @alignOf(Vec3), .fields = null, .field_count = 0 }, &pos));
    try testing.expect(pos != 0);

    for (0..512) |i| {
        const e = try ecsSpawn(f.ecs());
        const p: *Vec3 = @ptrCast(@alignCast((try ecsAttach(f.ecs(), e, pos)).?));
        p.x = @floatFromInt(i);
        p.y = 0.0;
        p.z = 0.0;
    }

    const read_terms = [_]abi_runtime.ke_component_access{access(pos, abi_runtime.KE_ACCESS_READ)};

    var a = systemParams("ReaderA", abi_runtime.KE_PHASE_UPDATE);
    withQueries(&a, &.{queryOf(&read_terms)});
    a.execute = &parallelReaderBody;

    var b = a;
    b.name = "ReaderB";

    try testing.expect(systemId(f.rt(), &a) != 0);
    try testing.expect(systemId(f.rt(), &b) != 0);

    const sysz = [_]abi_runtime.ke_runtime_system_params{ a, b };
    var waves = [_]u32{ 0, 0 };
    _ = orderOf(&sysz, .{}, &waves);
    try testing.expectEqual(waves[0], waves[1]);

    for (0..300) |_| try testing.expect(f.tick(1.0 / 60.0));
}

var g_pv_sum: f64 = 0.0;

fn posVelBody(ctx: ?*abi_runtime.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    var seg_count: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &seg_count);
    if (segs == null) return R.ok;
    for (0..seg_count) |s| {
        const pc: [*]const Vec3 = @ptrCast(@alignCast(segs.?[s].columns.?[0] orelse continue));
        const vc: [*]const Vec3 = @ptrCast(@alignCast(segs.?[s].columns.?[1] orelse continue));
        for (0..segs.?[s].count) |i| g_pv_sum += @as(f64, pc[i].x) + @as(f64, vc[i].x);
    }
    return R.ok;
}

test "a multi term query hands back aligned columns" {
    var f = try Fixture.init();
    defer f.deinit();

    var pos: abi_ecs.ke_component_id = 0;
    try R.check(f.ecs().component_register.?(f.ecs(), &abi_ecs.ke_component_params{ .name = "pos2", .size = @sizeOf(Vec3), .alignment = @alignOf(Vec3), .fields = null, .field_count = 0 }, &pos));
    var vel: abi_ecs.ke_component_id = 0;
    try R.check(f.ecs().component_register.?(f.ecs(), &abi_ecs.ke_component_params{ .name = "vel2", .size = @sizeOf(Vec3), .alignment = @alignOf(Vec3), .fields = null, .field_count = 0 }, &vel));
    try testing.expect(pos != 0);
    try testing.expect(vel != 0);

    var expect: f64 = 0.0;
    for (0..100) |i| {
        const e = try ecsSpawn(f.ecs());
        _ = (try ecsAttach(f.ecs(), e, pos));
        _ = (try ecsAttach(f.ecs(), e, vel));
        const p: *Vec3 = @ptrCast(@alignCast(f.ecs().component_get.?(f.ecs(), e, pos).?));
        const v: *Vec3 = @ptrCast(@alignCast(f.ecs().component_get.?(f.ecs(), e, vel).?));
        p.x = @floatFromInt(i);
        v.x = @floatFromInt(i * 2);
        expect += @as(f64, @floatFromInt(i)) + @as(f64, @floatFromInt(i * 2));
    }

    const q_terms = [_]abi_runtime.ke_component_access{ access(pos, abi_runtime.KE_ACCESS_READ), access(vel, abi_runtime.KE_ACCESS_READ) };

    var s = systemParams("PosVel", abi_runtime.KE_PHASE_UPDATE);
    withQueries(&s, &.{queryOf(&q_terms)});
    s.execute = &posVelBody;
    try testing.expect(systemId(f.rt(), &s) != 0);

    g_pv_sum = 0.0;
    try testing.expect(f.tick(1.0 / 60.0));
    try testing.expectEqual(expect, g_pv_sum);
}

test "creating, ticking and destroying a runtime leaves no block allocated" {
    var f = try Fixture.init();
    var sys = systemParams("LeakProbe", abi_runtime.KE_PHASE_UPDATE);
    sys.execute = &repeatSpawnerBody;
    try testing.expect(systemId(f.rt(), &sys) != 0);
    try testing.expect(f.tick(1.0 / 60.0));
    f.deinit();
    try heap.expectNoLeaks();
}

test "a runtime with no system registered leaves no block allocated" {
    var f = try Fixture.init();
    f.deinit();
    try heap.expectNoLeaks();
}
