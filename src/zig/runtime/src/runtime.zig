const std = @import("std");

const c = @cImport({
    @cInclude("kernel_engine/runtime/runtime_create.h");
    @cInclude("kernel_engine/runtime/system_ctx.h");
});

// Zig-native error translation at the C-ABI seam (no ke_common link).
const E = @import("kerror").Errors(c);

// In-house scheduler: ke_system_ctx is the only door to component memory inside
// an execute call; sequential phase walk with Bevy-style R/W wave grouping,
// enki-backed dispatch, a per-wave defer queue, and a fixed-timestep
// accumulator. Sim N+1 ‖ render N pipelining per RuntimeArchitectureV2.md §16.

const KE_MAX_QUERIES_PER_SYSTEM = 8;
const KE_MAX_SEGMENTS_PER_QUERY = 32;
const KE_RUNTIME_MAX_SYSTEMS_PER_PHASE = 256;
const MAX_TERMS = c.KE_QUERY_MAX_TERMS;

const ACCESS_WRITE: c_uint = @intCast(c.KE_ACCESS_WRITE);

// ── allocation helpers ───────────────────────────────────────────────────────
//
// Every buffer here has its length tracked alongside it (a *_capacity field,
// or a fixed KE_MAX_* size for the storage that never grows), so a Zig slice
// can always be reconstructed at the point of freeing.

const heap = @import("heap.zig");

fn cAlloc(comptime T: type, n: usize) ?[*]T {
    if (n == 0) return null;
    const slice = heap.gpa.alloc(T, n) catch return null;
    return slice.ptr;
}

fn cFree(comptime T: type, p: ?[*]T, n: usize) void {
    if (p) |pp| heap.gpa.free(pp[0..n]);
}

/// For the byte-sized per-column buffers, whose element type is only known at
/// runtime (it comes from the ECS's component_size).
fn cAllocBytes(n: usize) ?*anyopaque {
    if (n == 0) return null;
    const slice = heap.gpa.alloc(u8, n) catch return null;
    return slice.ptr;
}

fn cFreeBytes(p: ?*anyopaque, n: usize) void {
    if (p) |pp| heap.gpa.free(@as([*]u8, @ptrCast(pp))[0..n]);
}

// ── Defer queue ─────────────────────────────────────────────────────────────

const DeferKind = enum(c_int) {
    spawn = 1,
    attach = 2,
    detach = 3,
    despawn = 4,
    callback = 5,
};

const DeferCommand = struct {
    kind: DeferKind,
    entity: c.ke_entity,
    spawn_out: ?*c.ke_entity,
    cid: c.ke_component_id,
    attach_offset: usize,
    attach_size: usize,
    fn_: c.ke_defer_fn,
};

const DeferQueue = struct {
    cmds: ?[*]DeferCommand = null,
    count: usize = 0,
    capacity: usize = 0,
    arena: ?[*]u8 = null,
    arena_used: usize = 0,
    arena_capacity: usize = 0,
};

// Runtime-private state behind ke_system_ctx.handle. The public vtable struct
// (c.ke_system_ctx) lives in system_ctx.h; bindCtx wires its slots to the
// exported ke_system_ctx_* functions and points handle here.
const CtxState = struct {
    ecs: ?*c.ke_ecs,
    access_list: ?[*]const c.ke_component_access,
    access_count: u32,
    system_name: [*c]const u8,
    defer_q: ?*DeferQueue,
    seg_storage: ?[*]const c.ke_ecs_segment,
    seg_counts: ?[*]const usize,
    view_query_count: u32,
};

fn ctxOf(ptr: ?*c.ke_system_ctx) ?*CtxState {
    const ctx = ptr orelse return null;
    return @ptrCast(@alignCast(ctx.handle));
}

fn bindCtx(ctx: *c.ke_system_ctx, state: *CtxState) void {
    ctx.handle = state;
    ctx.view = &ke_system_ctx_view;
    ctx.reserve = &ke_system_ctx_reserve;
    ctx.@"defer" = &ke_system_ctx_defer;
    ctx.spawn = &ke_system_ctx_spawn;
    ctx.attach = &ke_system_ctx_attach;
    ctx.detach = &ke_system_ctx_detach;
    ctx.despawn = &ke_system_ctx_despawn;
}

// ── Wave builder (Bevy-style R/W conflict grouping) ─────────────────────────

fn termWrites(a: c.ke_component_access) bool {
    return (@as(c_uint, @intCast(a.access)) & ACCESS_WRITE) != 0;
}

fn paramsAccesses(p: *const c.ke_runtime_system_params, cid: c.ke_component_id, out_writes: *bool) bool {
    var any = false;
    var writes = false;
    if (p.queries) |queries| {
        for (0..p.query_count) |q| {
            const qd = &queries[q];
            for (0..qd.term_count) |t| {
                if (qd.terms[t].cid == cid) {
                    any = true;
                    if (termWrites(qd.terms[t])) writes = true;
                }
            }
        }
    }
    if (p.access_list) |list| {
        for (0..p.access_count) |i| {
            if (list[i].cid == cid) {
                any = true;
                if (termWrites(list[i])) writes = true;
            }
        }
    }
    out_writes.* = writes;
    return any;
}

fn conflictOnTerm(b: *const c.ke_runtime_system_params, cid: c.ke_component_id, a_writes: bool) bool {
    var b_writes = false;
    return paramsAccesses(b, cid, &b_writes) and (a_writes or b_writes);
}

fn systemsConflict(a: *const c.ke_runtime_system_params, b: *const c.ke_runtime_system_params) bool {
    if (a.queries) |queries| {
        for (0..a.query_count) |q| {
            const qd = &queries[q];
            for (0..qd.term_count) |t| {
                const a_writes = termWrites(qd.terms[t]);
                if (conflictOnTerm(b, qd.terms[t].cid, a_writes)) return true;
            }
        }
    }
    if (a.access_list) |list| {
        for (0..a.access_count) |i| {
            const a_writes = termWrites(list[i]);
            if (conflictOnTerm(b, list[i].cid, a_writes)) return true;
        }
    }
    return false;
}

export fn ke_runtime_debug_compute_waves(
    systems: [*c]const c.ke_runtime_system_params,
    system_count: u32,
    out_wave_assignments: [*c]u32,
    out_wave_count: [*c]u32,
) callconv(.c) void {
    if (out_wave_count == null) return;
    out_wave_count.* = 0;
    if (system_count == 0) return;
    if (systems == null or out_wave_assignments == null) return;

    var current_wave: u32 = 0;
    out_wave_assignments[0] = 0;
    var wave_start: u32 = 0;

    var i: u32 = 0;
    while (i < system_count) : (i += 1) {
        if (i == 0) {
            out_wave_assignments[0] = 0;
            continue;
        }
        var open_new = false;
        var j: u32 = wave_start;
        const si_ptr: *const c.ke_runtime_system_params = @ptrCast(&systems[i]);
        while (j < i) : (j += 1) {
            if (out_wave_assignments[j] != current_wave) continue;
            const sj_ptr: *const c.ke_runtime_system_params = @ptrCast(&systems[j]);
            if (systemsConflict(si_ptr, sj_ptr)) {
                open_new = true;
                break;
            }
        }
        if (open_new) {
            current_wave += 1;
            wave_start = i;
        }
        out_wave_assignments[i] = current_wave;
    }
    out_wave_count.* = current_wave + 1;
}

// ── ke_system_ctx public API ────────────────────────────────────────────────

export fn ke_system_ctx_view(ctx: ?*c.ke_system_ctx, query_index: u32, out_count: [*c]usize) callconv(.c) [*c]const c.ke_ecs_segment {
    if (out_count != null) out_count.* = 0;
    const s = ctxOf(ctx) orelse return null;
    if (s.seg_storage == null or query_index >= s.view_query_count) return null;
    if (out_count != null) out_count.* = s.seg_counts.?[query_index];
    return &s.seg_storage.?[@as(usize, query_index) * KE_MAX_SEGMENTS_PER_QUERY];
}

fn deferReserve(q: *DeferQueue, needed: usize) bool {
    if (needed <= q.capacity) return true;
    var new_cap: usize = if (q.capacity != 0) q.capacity * 2 else 16;
    while (new_cap < needed) new_cap *= 2;
    const buf = cAlloc(DeferCommand, new_cap) orelse return false;
    if (q.cmds) |old| {
        @memcpy(buf[0..q.count], old[0..q.count]);
        cFree(DeferCommand, old, q.capacity);
    }
    q.cmds = buf;
    q.capacity = new_cap;
    return true;
}

// Returns the byte offset where the bytes landed (maxUsize on OOM).
fn deferArenaPush(q: *DeferQueue, data: ?*const anyopaque, size: usize) usize {
    if (size == 0) return 0;
    if (q.arena_used + size > q.arena_capacity) {
        var new_cap: usize = if (q.arena_capacity != 0) q.arena_capacity * 2 else 256;
        while (new_cap < q.arena_used + size) new_cap *= 2;
        const buf = cAlloc(u8, new_cap) orelse return std.math.maxInt(usize);
        if (q.arena) |old| {
            @memcpy(buf[0..q.arena_used], old[0..q.arena_used]);
            cFree(u8, old, q.arena_capacity);
        }
        q.arena = buf;
        q.arena_capacity = new_cap;
    }
    const offset = q.arena_used;
    if (data) |d| {
        const src: [*]const u8 = @ptrCast(d);
        @memcpy(q.arena.?[offset .. offset + size], src[0..size]);
    }
    q.arena_used += size;
    return offset;
}

export fn ke_system_ctx_reserve(ctx: ?*c.ke_system_ctx) callconv(.c) c.ke_entity {
    const s = ctxOf(ctx) orelse return c.KE_ENTITY_INVALID;
    const ecs = s.ecs orelse return c.KE_ENTITY_INVALID;
    const reserve = ecs.entity_reserve orelse return c.KE_ENTITY_INVALID;
    return reserve(ecs);
}

export fn ke_system_ctx_defer(ctx: ?*c.ke_system_ctx, func: c.ke_defer_fn, user: ?*const anyopaque, user_size: usize) callconv(.c) bool {
    const s = ctxOf(ctx) orelse return false;
    const q = s.defer_q orelse return false;
    if (func == null) return false;
    const offset = deferArenaPush(q, user, user_size);
    if (offset == std.math.maxInt(usize)) return false;
    if (!deferReserve(q, q.count + 1)) return false;
    const cmd = &q.cmds.?[q.count];
    q.count += 1;
    cmd.kind = .callback;
    cmd.fn_ = func;
    cmd.attach_offset = offset;
    cmd.attach_size = user_size;
    return true;
}

export fn ke_system_ctx_spawn(ctx: ?*c.ke_system_ctx) callconv(.c) c.ke_entity {
    const s = ctxOf(ctx) orelse return c.KE_ENTITY_INVALID;
    const q = s.defer_q orelse return c.KE_ENTITY_INVALID;
    if (!deferReserve(q, q.count + 1)) return c.KE_ENTITY_INVALID;
    const cmd = &q.cmds.?[q.count];
    q.count += 1;
    cmd.kind = .spawn;
    cmd.spawn_out = null;
    // Placeholder; actual id assigned at flush. Caller must not use before flush.
    return c.KE_ENTITY_INVALID;
}

export fn ke_system_ctx_attach(ctx: ?*c.ke_system_ctx, entity: c.ke_entity, cid: c.ke_component_id, data: ?*const anyopaque, size: usize) callconv(.c) bool {
    const s = ctxOf(ctx) orelse return false;
    const q = s.defer_q orelse return false;
    const offset = deferArenaPush(q, data, size);
    if (offset == std.math.maxInt(usize)) return false;
    if (!deferReserve(q, q.count + 1)) return false;
    const cmd = &q.cmds.?[q.count];
    q.count += 1;
    cmd.kind = .attach;
    cmd.entity = entity;
    cmd.cid = cid;
    cmd.attach_offset = offset;
    cmd.attach_size = size;
    return true;
}

export fn ke_system_ctx_detach(ctx: ?*c.ke_system_ctx, entity: c.ke_entity, cid: c.ke_component_id) callconv(.c) bool {
    const s = ctxOf(ctx) orelse return false;
    const q = s.defer_q orelse return false;
    if (!deferReserve(q, q.count + 1)) return false;
    const cmd = &q.cmds.?[q.count];
    q.count += 1;
    cmd.kind = .detach;
    cmd.entity = entity;
    cmd.cid = cid;
    return true;
}

export fn ke_system_ctx_despawn(ctx: ?*c.ke_system_ctx, entity: c.ke_entity) callconv(.c) bool {
    const s = ctxOf(ctx) orelse return false;
    const q = s.defer_q orelse return false;
    if (!deferReserve(q, q.count + 1)) return false;
    const cmd = &q.cmds.?[q.count];
    q.count += 1;
    cmd.kind = .despawn;
    cmd.entity = entity;
    return true;
}

var s_defer_applied_total: u32 = 0;

fn deferFlush(q: *DeferQueue, ecs: *c.ke_ecs) void {
    for (0..q.count) |i| {
        const cmd = &q.cmds.?[i];
        switch (cmd.kind) {
            .spawn => {
                const e = ecs.entity_create.?(ecs);
                if (cmd.spawn_out) |so| so.* = e;
            },
            .attach => {
                const slot = ecs.component_add.?(ecs, cmd.entity, cmd.cid);
                if (slot != null and cmd.attach_size > 0) {
                    const dst: [*]u8 = @ptrCast(slot.?);
                    @memcpy(dst[0..cmd.attach_size], q.arena.?[cmd.attach_offset .. cmd.attach_offset + cmd.attach_size]);
                }
            },
            .detach => ecs.component_remove.?(ecs, cmd.entity, cmd.cid),
            .despawn => ecs.entity_destroy.?(ecs, cmd.entity),
            .callback => {
                if (cmd.fn_) |f| f(ecs, q.arena.? + cmd.attach_offset);
            },
        }
        s_defer_applied_total += 1;
    }
    q.count = 0; // drain — capacity retained
    q.arena_used = 0; // arena rewinds — capacity retained
}

export fn ke_system_ctx_defer_applied_count() callconv(.c) u32 {
    return s_defer_applied_total;
}
export fn ke_system_ctx_reset_defer_applied() callconv(.c) void {
    s_defer_applied_total = 0;
}

// ── Runtime state ───────────────────────────────────────────────────────────

const ExtractedQuery = struct {
    seg: c.ke_ecs_segment,
    entities_buf: ?[*]c.ke_entity,
    col_bufs: [MAX_TERMS]?*anyopaque,
    col_elem_size: [MAX_TERMS]usize,
    capacity: usize,
    elem_sizes_cached: bool,
};

const RegisteredSystem = struct {
    params: c.ke_runtime_system_params,
    query_decls: [KE_MAX_QUERIES_PER_SYSTEM]c.ke_query_decl,
    query_ids: [KE_MAX_QUERIES_PER_SYSTEM]c.ke_query_id,
    query_count: u32,
    seg_storage: ?[*]c.ke_ecs_segment,
    seg_counts: [KE_MAX_QUERIES_PER_SYSTEM]usize,
    extracted: [KE_MAX_QUERIES_PER_SYSTEM]ExtractedQuery,
    derived_access: [KE_MAX_QUERIES_PER_SYSTEM * MAX_TERMS]c.ke_component_access,
    derived_access_count: u32,
};

const RenderJob = struct {
    h: *RuntimeHandle,
    dt: f32,
};

const RuntimeState = struct {
    ecs: *c.ke_ecs,
    scheduler: *c.ke_scheduler,
    systems: ?[*]?*RegisteredSystem,
    system_count: usize,
    system_capacity: usize,
    next_module_id: u64,
    next_system_id: u64,
    fixed_dt: f32,
    fixed_dt_max_accum: f32,
    fixed_accumulator: f32,
    systems_prepared: usize,
    pending_render_task: ?*c.ke_task,
    render_job: ?*RenderJob,
};

const RuntimeHandle = struct {
    api: c.ke_runtime,
    state: RuntimeState,
};

fn handleOf(self: *c.ke_runtime) *RuntimeHandle {
    return @ptrCast(@alignCast(self.handle));
}

// ── Vtable impls ────────────────────────────────────────────────────────────

fn runtimeRegisterModule(self: ?*c.ke_runtime, p: [*c]const c.ke_runtime_module_params, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_module_id {
    if (self == null or self.?.handle == null or p == null or p.*.on_load == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return 0;
    }
    const h = handleOf(self.?);
    h.state.next_module_id += 1;
    const id = h.state.next_module_id;
    if (!p.*.on_load.?(self, p.*.user_data, out_error)) return 0;
    return id;
}

fn runtimeRegisterSystem(self: ?*c.ke_runtime, p: [*c]const c.ke_runtime_system_params, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_system_id {
    if (self == null or self.?.handle == null or p == null or p.*.execute == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return 0;
    }
    const h = handleOf(self.?);

    if (h.state.system_count == h.state.system_capacity) {
        const new_cap: usize = if (h.state.system_capacity != 0) h.state.system_capacity * 2 else 4;
        const new_buf = cAlloc(?*RegisteredSystem, new_cap) orelse {
            E.fail(out_error, .out_of_memory, "system array allocation failed", @src());
            return 0;
        };
        if (h.state.systems) |old| {
            @memcpy(new_buf[0..h.state.system_count], old[0..h.state.system_count]);
            cFree(?*RegisteredSystem, old, h.state.system_capacity);
        }
        h.state.systems = new_buf;
        h.state.system_capacity = new_cap;
    }

    const rs_mem = cAlloc(RegisteredSystem, 1) orelse {
        E.fail(out_error, .out_of_memory, "registered_system allocation failed", @src());
        return 0;
    };
    const rs = &rs_mem[0];
    h.state.systems.?[h.state.system_count] = rs;
    h.state.system_count += 1;

    rs.params = p.*;
    rs.query_count = 0;
    rs.seg_storage = null;
    rs.derived_access_count = 0;
    @memset(std.mem.asBytes(&rs.extracted), 0);

    if (p.*.queries != null and p.*.query_count > 0) {
        var qn = p.*.query_count;
        if (qn > KE_MAX_QUERIES_PER_SYSTEM) qn = KE_MAX_QUERIES_PER_SYSTEM;

        for (0..qn) |q| {
            const qd = &p.*.queries[q];
            var tn = qd.term_count;
            if (tn > MAX_TERMS) tn = MAX_TERMS;

            rs.query_decls[q] = qd.*;
            rs.query_decls[q].term_count = tn;
            rs.query_ids[q] = c.KE_QUERY_INVALID;

            for (0..tn) |t| {
                var found = false;
                for (0..rs.derived_access_count) |d| {
                    if (rs.derived_access[d].cid == qd.terms[t].cid) {
                        rs.derived_access[d].access |= qd.terms[t].access;
                        found = true;
                        break;
                    }
                }
                if (!found and rs.derived_access_count < KE_MAX_QUERIES_PER_SYSTEM * MAX_TERMS) {
                    rs.derived_access[rs.derived_access_count].cid = qd.terms[t].cid;
                    rs.derived_access[rs.derived_access_count].access = qd.terms[t].access;
                    rs.derived_access_count += 1;
                }
            }
        }
        rs.query_count = qn;

        // Fold direct access entries into the derived list too.
        for (0..p.*.access_count) |i| {
            var found = false;
            for (0..rs.derived_access_count) |d| {
                if (rs.derived_access[d].cid == p.*.access_list[i].cid) {
                    rs.derived_access[d].access |= p.*.access_list[i].access;
                    found = true;
                    break;
                }
            }
            if (!found and rs.derived_access_count < KE_MAX_QUERIES_PER_SYSTEM * MAX_TERMS) {
                rs.derived_access[rs.derived_access_count] = p.*.access_list[i];
                rs.derived_access_count += 1;
            }
        }

        rs.params.access_list = &rs.derived_access;
        rs.params.access_count = rs.derived_access_count;
        rs.params.queries = null;
        rs.params.query_count = 0;

        rs.seg_storage = cAlloc(c.ke_ecs_segment, KE_MAX_QUERIES_PER_SYSTEM * KE_MAX_SEGMENTS_PER_QUERY) orelse {
            h.state.system_count -= 1;
            E.fail(out_error, .out_of_memory, "query segment storage allocation failed", @src());
            return 0;
        };
    }

    h.state.next_system_id += 1;
    return h.state.next_system_id;
}

// ── Wave dispatch ───────────────────────────────────────────────────────────

const TaskPkg = struct {
    state: CtxState, // runtime-private; ctx.handle points here
    ctx: c.ke_system_ctx, // public vtable handed to the system body
    execute: ?*const fn (?*c.ke_system_ctx, ?*anyopaque, f32) callconv(.c) void,
    user_data: ?*anyopaque,
    dt: f32,
    defer_q: DeferQueue,
};

fn taskPkgRun(data: ?*anyopaque) callconv(.c) void {
    const pkg: *TaskPkg = @ptrCast(@alignCast(data.?));
    pkg.state.defer_q = &pkg.defer_q;
    pkg.execute.?(&pkg.ctx, pkg.user_data, pkg.dt);
}

const WaveRunCtx = struct {
    h: *RuntimeHandle,
    pkgs: [*]TaskPkg,
    tasks: [*]?*c.ke_task,
    pinned: [*]u32,
    wave_size: u32,
};

fn runWaveBody(wc: *WaveRunCtx) void {
    const sched = wc.h.state.scheduler;
    var t: u32 = 0;
    while (t < wc.wave_size) : (t += 1) {
        if (wc.pinned[t] > 0)
            wc.tasks[t] = sched.dispatch_pinned.?(sched, wc.pinned[t], taskPkgRun, &wc.pkgs[t])
        else
            wc.tasks[t] = sched.dispatch.?(sched, taskPkgRun, &wc.pkgs[t]);
    }
    t = 0;
    while (t < wc.wave_size) : (t += 1) {
        sched.wait.?(sched, wc.tasks[t]);
    }
}

fn runtimeRunPhase(h: *RuntimeHandle, phase: c.ke_phase, dt: f32) void {
    if (h.state.system_count == 0) return;

    var phase_indices: [KE_RUNTIME_MAX_SYSTEMS_PER_PHASE]u32 = undefined;
    var phase_params: [KE_RUNTIME_MAX_SYSTEMS_PER_PHASE]c.ke_runtime_system_params = undefined;
    var phase_count: u32 = 0;
    for (0..h.state.system_count) |si| {
        const rs = h.state.systems.?[si].?;
        if (rs.params.phase != phase) continue;
        if (rs.params.execute == null) continue;
        if (phase_count >= KE_RUNTIME_MAX_SYSTEMS_PER_PHASE) break;
        phase_indices[phase_count] = @intCast(si);
        phase_params[phase_count] = rs.params;
        phase_count += 1;
    }
    if (phase_count == 0) return;

    var wave_assignments: [KE_RUNTIME_MAX_SYSTEMS_PER_PHASE]u32 = undefined;
    var wave_count: u32 = 0;
    ke_runtime_debug_compute_waves(&phase_params, phase_count, &wave_assignments, &wave_count);

    var pkgs: [KE_RUNTIME_MAX_SYSTEMS_PER_PHASE]TaskPkg = undefined;
    var tasks: [KE_RUNTIME_MAX_SYSTEMS_PER_PHASE]?*c.ke_task = undefined;
    var pinned: [KE_RUNTIME_MAX_SYSTEMS_PER_PHASE]u32 = undefined;

    var w: u32 = 0;
    while (w < wave_count) : (w += 1) {
        var wave_size: u32 = 0;

        for (0..phase_count) |k| {
            if (wave_assignments[k] != w) continue;
            const rs = h.state.systems.?[phase_indices[k]].?;

            const pkg = &pkgs[wave_size];
            bindCtx(&pkg.ctx, &pkg.state);
            pkg.state.ecs = h.state.ecs;
            pkg.state.access_list = rs.params.access_list;
            pkg.state.access_count = rs.params.access_count;
            pkg.state.system_name = rs.params.name;
            pkg.state.defer_q = null;

            if (rs.query_count > 0 and rs.seg_storage != null) {
                if (phase != c.KE_PHASE_RENDER and h.state.ecs.query_resolve != null) {
                    for (0..rs.query_count) |q| {
                        const dst = &rs.seg_storage.?[q * KE_MAX_SEGMENTS_PER_QUERY];
                        var cnt: usize = 0;
                        h.state.ecs.query_resolve.?(h.state.ecs, rs.query_ids[q], dst, KE_MAX_SEGMENTS_PER_QUERY, &cnt);
                        rs.seg_counts[q] = cnt;
                    }
                }
                pkg.state.seg_storage = rs.seg_storage;
                pkg.state.seg_counts = &rs.seg_counts;
                pkg.state.view_query_count = rs.query_count;
            } else {
                pkg.state.seg_storage = null;
                pkg.state.seg_counts = null;
                pkg.state.view_query_count = 0;
            }
            pkg.execute = rs.params.execute;
            pkg.user_data = rs.params.user_data;
            pkg.dt = dt;
            pkg.defer_q = .{};
            pinned[wave_size] = rs.params.pinned_thread;
            wave_size += 1;
        }

        var wc = WaveRunCtx{ .h = h, .pkgs = &pkgs, .tasks = &tasks, .pinned = &pinned, .wave_size = wave_size };
        runWaveBody(&wc);

        // Wave barrier: flush each system's deferred changes in registration order.
        var t: u32 = 0;
        while (t < wave_size) : (t += 1) {
            deferFlush(&pkgs[t].defer_q, h.state.ecs);
            if (pkgs[t].defer_q.cmds) |cmds| cFree(DeferCommand, cmds, pkgs[t].defer_q.capacity);
            if (pkgs[t].defer_q.arena) |arena| cFree(u8, arena, pkgs[t].defer_q.arena_capacity);
        }
    }
}

fn runtimeBindQueries(h: *RuntimeHandle, first: usize, last: usize) void {
    if (h.state.ecs.query_register == null) return;
    for (first..last) |si| {
        const rs = h.state.systems.?[si].?;
        for (0..rs.query_count) |q| {
            const qd = &rs.query_decls[q];
            var cids: [MAX_TERMS]c.ke_component_id = undefined;
            for (0..qd.term_count) |t| cids[t] = qd.terms[t].cid;
            rs.query_ids[q] = h.state.ecs.query_register.?(h.state.ecs, &cids, qd.term_count);
        }
    }
}

fn runtimePrepareSystems(h: *RuntimeHandle) void {
    if (h.state.systems_prepared >= h.state.system_count) return;
    const first = h.state.systems_prepared;
    const last = h.state.system_count;
    runtimeBindQueries(h, first, last);
    h.state.systems_prepared = last;
}

fn runtimeExtractRenderState(h: *RuntimeHandle) void {
    if (h.state.ecs.query_resolve == null) return;
    var raw: [KE_MAX_SEGMENTS_PER_QUERY]c.ke_ecs_segment = undefined;

    for (0..h.state.system_count) |si| {
        const rs = h.state.systems.?[si].?;
        if (rs.params.phase != c.KE_PHASE_RENDER) continue;

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
            h.state.ecs.query_resolve.?(h.state.ecs, rs.query_ids[q], &raw, KE_MAX_SEGMENTS_PER_QUERY, &raw_count);

            var total: usize = 0;
            for (0..raw_count) |s| total += raw[s].count;

            if (total > eq.capacity) {
                var new_cap: usize = if (eq.capacity != 0) eq.capacity * 2 else 64;
                while (new_cap < total) new_cap *= 2;

                if (cAlloc(c.ke_entity, new_cap)) |new_ents| {
                    if (eq.entities_buf) |old| cFree(c.ke_entity, old, eq.capacity);
                    eq.entities_buf = new_ents;

                    for (0..qd.term_count) |t| {
                        if (eq.col_elem_size[t] == 0) continue;
                        const new_col = cAllocBytes(eq.col_elem_size[t] *% new_cap) orelse continue;
                        if (eq.col_bufs[t]) |oldc| cFreeBytes(oldc, eq.col_elem_size[t] *% eq.capacity);
                        eq.col_bufs[t] = new_col;
                    }
                    eq.capacity = new_cap;
                }
            }

            const cap = eq.capacity;
            var written: usize = 0;
            var s: usize = 0;
            while (s < raw_count and written < cap) : (s += 1) {
                var take = raw[s].count;
                if (written + take > cap) take = cap - written;
                if (eq.entities_buf) |ebuf| {
                    @memcpy(ebuf[written .. written + take], raw[s].entities[0..take]);
                }
                for (0..qd.term_count) |t| {
                    if (eq.col_elem_size[t] == 0 or eq.col_bufs[t] == null) continue;
                    const esz = eq.col_elem_size[t];
                    const dst: [*]u8 = @ptrCast(eq.col_bufs[t].?);
                    const src: [*]const u8 = @ptrCast(raw[s].columns[t].?);
                    @memcpy(dst[written * esz .. written * esz + take * esz], src[0 .. take * esz]);
                }
                written += take;
            }

            eq.seg.entities = if (eq.entities_buf) |eb| eb else null;
            eq.seg.count = written;
            for (0..qd.term_count) |t| {
                eq.seg.columns[t] = if (eq.col_elem_size[t] != 0) eq.col_bufs[t] else null;
            }
            var t2: usize = qd.term_count;
            while (t2 < MAX_TERMS) : (t2 += 1) eq.seg.columns[t2] = null;

            if (rs.seg_storage) |ss| {
                ss[q * KE_MAX_SEGMENTS_PER_QUERY] = eq.seg;
                rs.seg_counts[q] = if (written > 0) 1 else 0;
            }
        }
    }
}

fn renderJobRun(data: ?*anyopaque) callconv(.c) void {
    const job: *RenderJob = @ptrCast(@alignCast(data.?));
    runtimeRunPhase(job.h, c.KE_PHASE_RENDER, job.dt);
}

fn runtimeJoinPendingRender(h: *RuntimeHandle) void {
    const task = h.state.pending_render_task orelse return;
    h.state.scheduler.wait.?(h.state.scheduler, task);
    h.state.pending_render_task = null;
}

fn runtimeTick(self: ?*c.ke_runtime, dt: f32, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    if (self == null or self.?.handle == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    if (dt < 0.0) {
        E.fail(out_error, .invalid_argument, "negative dt", @src());
        return false;
    }
    const h = handleOf(self.?);

    runtimePrepareSystems(h);
    runtimeRunPhase(h, c.KE_PHASE_PRE_UPDATE, dt);

    h.state.fixed_accumulator += dt;
    if (h.state.fixed_accumulator > h.state.fixed_dt_max_accum) {
        h.state.fixed_accumulator = h.state.fixed_dt_max_accum;
    }
    while (h.state.fixed_accumulator >= h.state.fixed_dt) {
        runtimeRunPhase(h, c.KE_PHASE_FIXED_UPDATE, h.state.fixed_dt);
        h.state.fixed_accumulator -= h.state.fixed_dt;
    }

    runtimeRunPhase(h, c.KE_PHASE_UPDATE, dt);
    runtimeRunPhase(h, c.KE_PHASE_POST_UPDATE, dt);

    runtimeJoinPendingRender(h);
    runtimeExtractRenderState(h);

    if (h.state.render_job == null) {
        if (cAlloc(RenderJob, 1)) |rj| h.state.render_job = &rj[0];
    }
    if (h.state.render_job) |job| {
        job.h = h;
        job.dt = dt;
        h.state.pending_render_task = h.state.scheduler.dispatch.?(h.state.scheduler, renderJobRun, job);
    } else {
        runtimeRunPhase(h, c.KE_PHASE_RENDER, dt);
    }

    return true;
}

fn runtimeFlushRender(self: ?*c.ke_runtime) callconv(.c) void {
    if (self == null or self.?.handle == null) return;
    runtimeJoinPendingRender(handleOf(self.?));
}

fn runtimeDestroy(self: ?*c.ke_runtime) callconv(.c) void {
    if (self == null or self.?.handle == null) return;
    const h = handleOf(self.?);

    runtimeJoinPendingRender(h);
    if (h.state.render_job) |rj| cFree(RenderJob, @ptrCast(rj), 1);

    if (h.state.systems) |systems| {
        for (0..h.state.system_count) |i| {
            const rs = systems[i].?;
            if (rs.seg_storage) |ss| cFree(c.ke_ecs_segment, ss, KE_MAX_QUERIES_PER_SYSTEM * KE_MAX_SEGMENTS_PER_QUERY);
            for (0..KE_MAX_QUERIES_PER_SYSTEM) |q| {
                const eq = &rs.extracted[q];
                if (eq.entities_buf) |eb| cFree(c.ke_entity, eb, eq.capacity);
                for (0..MAX_TERMS) |t| {
                    if (eq.col_bufs[t]) |cb| cFreeBytes(cb, eq.col_elem_size[t] *% eq.capacity);
                }
            }
            cFree(RegisteredSystem, @ptrCast(rs), 1);
        }
        cFree(?*RegisteredSystem, systems, h.state.system_capacity);
    }
    cFree(RuntimeHandle, @ptrCast(h), 1);
}

// ── Factory ─────────────────────────────────────────────────────────────────

export fn ke_runtime_create(ecs: ?*c.ke_ecs, scheduler: ?*c.ke_scheduler, params: [*c]const c.ke_runtime_params, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_runtime_handle {
    const empty = c.ke_runtime_handle{ .ref = null, .destroy = null };
    if (ecs == null or scheduler == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return empty;
    }

    const h_mem = cAlloc(RuntimeHandle, 1) orelse {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return empty;
    };
    const h = &h_mem[0];
    @memset(std.mem.asBytes(h), 0);

    h.state.ecs = ecs.?;
    h.state.scheduler = scheduler.?;

    h.state.fixed_dt = if (params != null and params.*.fixed_dt > 0.0) params.*.fixed_dt else (1.0 / 60.0);
    h.state.fixed_dt_max_accum = if (params != null and params.*.fixed_dt_max_accum > 0.0) params.*.fixed_dt_max_accum else 0.25;

    h.api.handle = h;
    h.api.register_module = &runtimeRegisterModule;
    h.api.register_system = &runtimeRegisterSystem;
    h.api.tick = &runtimeTick;
    h.api.flush_render = &runtimeFlushRender;

    return .{ .ref = &h.api, .destroy = &runtimeDestroy };
}
