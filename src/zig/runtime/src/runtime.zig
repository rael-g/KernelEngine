const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

const c = @cImport({
    @cInclude("kernel_engine/runtime/runtime_create.h");
    @cInclude("kernel_engine/runtime/system_ctx.h");
});

const E = @import("kerror").Errors(c);

const KE_MAX_QUERIES_PER_SYSTEM = 8;
const KE_MAX_SEGMENTS_PER_QUERY = 32;
/// One scratch set per phase. runtimeRunPhase is re-entrant across threads —
/// the render phase is pipelined against the next tick's sim phases — so a
/// single shared set would let two threads write the same buffers.
const KE_RUNTIME_PHASE_COUNT = 7;
const MAX_TERMS = c.KE_QUERY_MAX_TERMS;

const ACCESS_WRITE: c_uint = @intCast(c.KE_ACCESS_WRITE);

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

const CtxState = struct {
    ecs: ?*c.ke_ecs,
    access_list: ?[*]const c.ke_component_access,
    access_count: u32,
    system_name: [*c]const u8,
    defer_q: ?*DeferQueue,
    seg_storage: ?[*]const c.ke_ecs_segment,
    seg_counts: ?[*]const usize,
    view_query_count: u32,
    slice_index: u32,
    slice_count: u32,
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
    ctx.slice = &ke_system_ctx_slice;
}

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

/// Payloads are copied into one byte arena and later handed back to a callback
/// that casts them to its own struct, so each has to start on an address that
/// struct could legally live at. Without this an odd-sized payload leaves the
/// next one misaligned, and the cast is undefined behaviour rather than a
/// visible failure.
const defer_arena_align: usize = 16;

fn deferArenaPush(q: *DeferQueue, data: ?*const anyopaque, size: usize) usize {
    if (size == 0) return 0;
    q.arena_used = std.mem.alignForward(usize, q.arena_used, defer_arena_align);
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

/// Returns the id the entity will have, usable immediately — a system that spawns
/// something almost always needs to give it components in the same body, and it
/// can only name it if the id exists now. The entity itself enters the world at
/// the wave barrier.
export fn ke_system_ctx_spawn(ctx: ?*c.ke_system_ctx) callconv(.c) c.ke_entity {
    const s = ctxOf(ctx) orelse return c.KE_ENTITY_INVALID;
    const q = s.defer_q orelse return c.KE_ENTITY_INVALID;
    const ecs = s.ecs orelse return c.KE_ENTITY_INVALID;
    const reserve = ecs.entity_reserve orelse return c.KE_ENTITY_INVALID;
    const entity = reserve(ecs);
    if (entity == c.KE_ENTITY_INVALID) return c.KE_ENTITY_INVALID;
    if (!deferReserve(q, q.count + 1)) return c.KE_ENTITY_INVALID;
    const cmd = &q.cmds.?[q.count];
    q.count += 1;
    cmd.kind = .spawn;
    cmd.entity = entity;
    return entity;
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

export fn ke_system_ctx_slice(ctx: ?*c.ke_system_ctx, out_index: [*c]u32, out_count: [*c]u32) callconv(.c) void {
    const s = ctxOf(ctx);
    if (out_index != null) out_index.* = if (s) |st| st.slice_index else 0;
    if (out_count != null) out_count.* = if (s) |st| st.slice_count else 1;
}

var s_defer_applied_total: u32 = 0;

fn deferFlush(q: *DeferQueue, ecs: *c.ke_ecs) void {
    for (0..q.count) |i| {
        const cmd = &q.cmds.?[i];
        switch (cmd.kind) {
            .spawn => {
                if (ecs.entity_materialize) |materialize| materialize(ecs, cmd.entity);
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
    q.count = 0;
    q.arena_used = 0;
}

export fn ke_system_ctx_defer_applied_count() callconv(.c) u32 {
    return s_defer_applied_total;
}
export fn ke_system_ctx_reset_defer_applied() callconv(.c) void {
    s_defer_applied_total = 0;
}

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
    max_systems_per_phase: u32,
    phase_indices: ?[*]u32,
    phase_params: ?[*]c.ke_runtime_system_params,
    wave_assignments: ?[*]u32,
    phase_pkgs: ?[*]TaskPkg,
    phase_tasks: ?[*]?*c.ke_task,
    phase_pinned: ?[*]u32,
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

    var in_phase: u32 = 0;
    for (0..h.state.system_count) |si| {
        if (h.state.systems.?[si].?.params.phase == p.*.phase) in_phase += 1;
    }
    if (in_phase >= h.state.max_systems_per_phase) {
        E.fail(out_error, .out_of_memory, "phase is at its max_systems_per_phase limit", @src());
        return 0;
    }

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

const TaskPkg = struct {
    state: CtxState,
    ctx: c.ke_system_ctx,
    execute: ?*const fn (?*c.ke_system_ctx, ?*anyopaque, f32) callconv(.c) void,
    user_data: ?*anyopaque,
    dt: f32,
    defer_q: DeferQueue,
    allow_defer: bool,
};

fn taskPkgRun(data: ?*anyopaque) callconv(.c) void {
    const pkg: *TaskPkg = @ptrCast(@alignCast(data.?));
    if (pkg.allow_defer) pkg.state.defer_q = &pkg.defer_q;
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

fn freePhaseScratch(h: *RuntimeHandle) void {
    const n: usize = @as(usize, h.state.max_systems_per_phase) * KE_RUNTIME_PHASE_COUNT;
    cFree(u32, h.state.phase_indices, n);
    cFree(c.ke_runtime_system_params, h.state.phase_params, n);
    cFree(u32, h.state.wave_assignments, n);
    cFree(TaskPkg, h.state.phase_pkgs, n);
    cFree(?*c.ke_task, h.state.phase_tasks, n);
    cFree(u32, h.state.phase_pinned, n);
    h.state.phase_indices = null;
    h.state.phase_params = null;
    h.state.wave_assignments = null;
    h.state.phase_pkgs = null;
    h.state.phase_tasks = null;
    h.state.phase_pinned = null;
}

fn runtimeRunPhase(h: *RuntimeHandle, phase: c.ke_phase, dt: f32) void {
    if (h.state.system_count == 0) return;

    const cap: usize = h.state.max_systems_per_phase;
    const base: usize = @as(usize, @intCast(phase)) * cap;
    const phase_indices = (h.state.phase_indices orelse return) + base;
    const phase_params = (h.state.phase_params orelse return) + base;
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
    if (phase_count == 0) return;

    const wave_assignments = (h.state.wave_assignments orelse return) + base;
    var wave_count: u32 = 0;
    ke_runtime_debug_compute_waves(phase_params, phase_count, wave_assignments, &wave_count);

    const pkgs = (h.state.phase_pkgs orelse return) + base;
    const tasks = (h.state.phase_tasks orelse return) + base;
    const pinned = (h.state.phase_pinned orelse return) + base;

    var w: u32 = 0;
    while (w < wave_count) : (w += 1) {
        var wave_size: u32 = 0;

        for (0..phase_count) |k| {
            if (wave_assignments[k] != w) continue;
            const rs = h.state.systems.?[phase_indices[k]].?;

            if (rs.query_count > 0 and rs.seg_storage != null) {
                if (phase != c.KE_PHASE_RENDER and h.state.ecs.query_resolve != null) {
                    for (0..rs.query_count) |q| {
                        const dst = &rs.seg_storage.?[q * KE_MAX_SEGMENTS_PER_QUERY];
                        var cnt: usize = 0;
                        h.state.ecs.query_resolve.?(h.state.ecs, rs.query_ids[q], dst, KE_MAX_SEGMENTS_PER_QUERY, &cnt);
                        rs.seg_counts[q] = cnt;
                    }
                }
            }

            const slices = sliceCountFor(h, &rs.params, h.state.max_systems_per_phase - wave_size);
            var slice: u32 = 0;
            while (slice < slices) : (slice += 1) {
                const pkg = &pkgs[wave_size];
                bindCtx(&pkg.ctx, &pkg.state);
                pkg.state.ecs = h.state.ecs;
                pkg.state.access_list = rs.params.access_list;
                pkg.state.access_count = rs.params.access_count;
                pkg.state.system_name = rs.params.name;
                pkg.state.defer_q = null;
                pkg.state.slice_index = slice;
                pkg.state.slice_count = slices;

                if (rs.query_count > 0 and rs.seg_storage != null) {
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
                pkg.allow_defer = phase != c.KE_PHASE_RENDER;
                pinned[wave_size] = rs.params.pinned_thread;
                wave_size += 1;
            }
        }

        var wc = WaveRunCtx{ .h = h, .pkgs = pkgs, .tasks = tasks, .pinned = pinned, .wave_size = wave_size };
        runWaveBody(&wc);

        var t: u32 = 0;
        while (t < wave_size) : (t += 1) {
            deferFlush(&pkgs[t].defer_q, h.state.ecs);
            if (pkgs[t].defer_q.cmds) |cmds| cFree(DeferCommand, cmds, pkgs[t].defer_q.capacity);
            if (pkgs[t].defer_q.arena) |arena| cFree(u8, arena, pkgs[t].defer_q.arena_capacity);
        }
    }
}

/// How many concurrent slices one system's body is run as. A system that did not
/// promise per-entity independence, or that is pinned to a named thread, is always
/// one call; otherwise the entity set is split across the pool, never past the room
/// left in the phase's package storage.
fn sliceCountFor(h: *RuntimeHandle, p: *const c.ke_runtime_system_params, room: u32) u32 {
    if (room == 0) return 0;
    if (!p.per_entity or p.pinned_thread != 0) return 1;
    const sched = h.state.scheduler;
    const workers: u32 = if (sched.get_num_workers) |f| f(sched) else 0;
    if (workers <= 1) return 1;
    return @min(workers, room);
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
        freePhaseScratch(h);
    }
    cFree(RuntimeHandle, @ptrCast(h), 1);
}

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

    const max_per_phase: u32 = if (params != null and params.*.max_systems_per_phase > 0) params.*.max_systems_per_phase else 256;
    h.state.max_systems_per_phase = max_per_phase;
    const n: usize = @as(usize, max_per_phase) * KE_RUNTIME_PHASE_COUNT;
    h.state.phase_indices = cAlloc(u32, n);
    h.state.phase_params = cAlloc(c.ke_runtime_system_params, n);
    h.state.wave_assignments = cAlloc(u32, n);
    h.state.phase_pkgs = cAlloc(TaskPkg, n);
    h.state.phase_tasks = cAlloc(?*c.ke_task, n);
    h.state.phase_pinned = cAlloc(u32, n);
    if (h.state.phase_indices == null or h.state.phase_params == null or h.state.wave_assignments == null or
        h.state.phase_pkgs == null or h.state.phase_tasks == null or h.state.phase_pinned == null)
    {
        freePhaseScratch(h);
        cFree(RuntimeHandle, @ptrCast(h), 1);
        E.fail(out_error, .out_of_memory, "phase scratch allocation failed", @src());
        return empty;
    }

    h.api.handle = h;
    h.api.register_module = &runtimeRegisterModule;
    h.api.register_system = &runtimeRegisterSystem;
    h.api.tick = &runtimeTick;
    h.api.flush_render = &runtimeFlushRender;

    return .{ .ref = &h.api, .destroy = &runtimeDestroy };
}

const testing = std.testing;

extern fn ke_ecs_flecs_create(params: ?*const anyopaque, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_ecs_handle;
extern fn ke_scheduler_enki_create(out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_scheduler_handle;

const Fixture = struct {
    scheduler_h: c.ke_scheduler_handle,
    ecs_h: c.ke_ecs_handle,
    runtime_h: c.ke_runtime_handle,

    fn init() !Fixture {
        const sh = ke_scheduler_enki_create(null);
        try testing.expect(sh.ref != null);

        const eh = ke_ecs_flecs_create(null, null);
        try testing.expect(eh.ref != null);

        var rp = std.mem.zeroes(c.ke_runtime_params);
        const rh = ke_runtime_create(eh.ref, sh.ref, &rp, null);
        try testing.expect(rh.ref != null);

        return .{ .scheduler_h = sh, .ecs_h = eh, .runtime_h = rh };
    }

    fn deinit(self: *Fixture) void {
        if (self.runtime_h.ref) |r| self.runtime_h.destroy.?(r);
        if (self.ecs_h.ref) |r| self.ecs_h.destroy.?(r);
        if (self.scheduler_h.ref) |r| self.scheduler_h.destroy.?(r);
    }

    fn rt(self: *Fixture) *c.ke_runtime {
        return @ptrCast(self.runtime_h.ref);
    }

    fn ecs(self: *Fixture) *c.ke_ecs {
        return @ptrCast(self.ecs_h.ref);
    }

    fn tick(self: *Fixture, dt: f32) bool {
        return self.rt().tick.?(self.rt(), dt, null);
    }

    fn flushRender(self: *Fixture) void {
        self.rt().flush_render.?(self.rt());
    }
};

fn access(cid: u32, mode: c_int) c.ke_component_access {
    return .{ .cid = cid, .access = @intCast(mode) };
}

fn systemParams(name: [*c]const u8, phase: c_int) c.ke_runtime_system_params {
    var s = std.mem.zeroes(c.ke_runtime_system_params);
    s.name = name;
    s.phase = @intCast(phase);
    return s;
}

fn noopSystem(_: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) void {}

const Counter = std.atomic.Value(u32);

fn countingSystem(_: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) void {
    const counter: *Counter = @ptrCast(@alignCast(ud.?));
    _ = counter.fetchAdd(1, .acq_rel);
}

const ModuleCtx = struct {
    load_calls: Counter = Counter.init(0),
    system_ticks: Counter = Counter.init(0),
};

fn moduleTickSystem(_: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) void {
    const ctx: *ModuleCtx = @ptrCast(@alignCast(ud.?));
    _ = ctx.system_ticks.fetchAdd(1, .acq_rel);
}

fn testModuleOnLoad(runtime: ?*c.ke_runtime, ud: ?*anyopaque, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const ctx: *ModuleCtx = @ptrCast(@alignCast(ud.?));
    _ = ctx.load_calls.fetchAdd(1, .acq_rel);

    var sys = systemParams("TickCounter", c.KE_PHASE_UPDATE);
    sys.user_data = ud;
    sys.execute = &moduleTickSystem;

    const rtp = runtime orelse return false;
    return rtp.register_system.?(rtp, &sys, null) != 0;
}

const SliceProbe = struct {
    calls: Counter = Counter.init(0),
    seen: [64]Counter = [_]Counter{Counter.init(0)} ** 64,
    reported_count: Counter = Counter.init(0),
};

fn sliceProbeSystem(ctx: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) void {
    const probe: *SliceProbe = @ptrCast(@alignCast(ud.?));
    var index: u32 = 99;
    var count: u32 = 99;
    ke_system_ctx_slice(ctx, &index, &count);
    _ = probe.calls.fetchAdd(1, .acq_rel);
    probe.reported_count.store(count, .release);
    if (index < probe.seen.len) _ = probe.seen[index].fetchAdd(1, .acq_rel);
}

test "a system that does not promise per-entity work runs as one slice" {
    var f = try Fixture.init();
    defer f.deinit();

    var probe = SliceProbe{};
    var sys = systemParams("Serial", c.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &sliceProbeSystem;
    try testing.expect(f.rt().register_system.?(f.rt(), &sys, null) != 0);

    try testing.expect(f.tick(1.0 / 60.0));

    try testing.expectEqual(@as(u32, 1), probe.calls.load(.acquire));
    try testing.expectEqual(@as(u32, 1), probe.reported_count.load(.acquire));
    try testing.expectEqual(@as(u32, 1), probe.seen[0].load(.acquire));
}

test "a per-entity system runs every slice of its set exactly once" {
    var f = try Fixture.init();
    defer f.deinit();

    var probe = SliceProbe{};
    var sys = systemParams("Sliced", c.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &sliceProbeSystem;
    sys.per_entity = true;
    try testing.expect(f.rt().register_system.?(f.rt(), &sys, null) != 0);

    try testing.expect(f.tick(1.0 / 60.0));

    const slices = probe.reported_count.load(.acquire);
    try testing.expect(slices >= 1);
    try testing.expectEqual(slices, probe.calls.load(.acquire));

    var i: u32 = 0;
    while (i < slices) : (i += 1)
        try testing.expectEqual(@as(u32, 1), probe.seen[i].load(.acquire));
}

test "a per-entity system pinned to a thread stays one slice" {
    var f = try Fixture.init();
    defer f.deinit();

    var probe = SliceProbe{};
    var sys = systemParams("PinnedSliced", c.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &sliceProbeSystem;
    sys.per_entity = true;
    sys.pinned_thread = 1;
    try testing.expect(f.rt().register_system.?(f.rt(), &sys, null) != 0);

    try testing.expect(f.tick(1.0 / 60.0));

    try testing.expectEqual(@as(u32, 1), probe.reported_count.load(.acquire));
    try testing.expectEqual(@as(u32, 1), probe.calls.load(.acquire));
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
    var mod = std.mem.zeroes(c.ke_runtime_module_params);
    mod.name = "TestModule";
    mod.user_data = &ctx;
    mod.on_load = &testModuleOnLoad;

    const mid = f.rt().register_module.?(f.rt(), &mod, null);
    try testing.expect(mid != 0);
    try testing.expectEqual(@as(u32, 1), ctx.load_calls.load(.acquire));
}

test "a registered system fires once per tick" {
    var f = try Fixture.init();
    defer f.deinit();

    var ctx = ModuleCtx{};
    var mod = std.mem.zeroes(c.ke_runtime_module_params);
    mod.name = "TickModule";
    mod.user_data = &ctx;
    mod.on_load = &testModuleOnLoad;

    try testing.expect(f.rt().register_module.?(f.rt(), &mod, null) != 0);

    for (0..10) |_| try testing.expect(f.tick(1.0 / 60.0));

    try testing.expectEqual(@as(u32, 10), ctx.system_ticks.load(.acquire));
}

test "registering a module with no params is refused" {
    var f = try Fixture.init();
    defer f.deinit();

    try testing.expectEqual(@as(c.ke_module_id, 0), f.rt().register_module.?(f.rt(), null, null));
}

test "registering a system with no execute body is refused" {
    var f = try Fixture.init();
    defer f.deinit();

    const sys = systemParams("Bad", c.KE_PHASE_UPDATE);
    try testing.expectEqual(@as(c.ke_system_id, 0), f.rt().register_system.?(f.rt(), &sys, null));
}

test "creating a runtime without an ecs is refused" {
    var f = try Fixture.init();
    defer f.deinit();

    var rp = std.mem.zeroes(c.ke_runtime_params);
    const rh = ke_runtime_create(null, f.scheduler_h.ref, &rp, null);
    try testing.expect(rh.ref == null);
}

test "creating a runtime without a scheduler is refused" {
    var f = try Fixture.init();
    defer f.deinit();

    var rp = std.mem.zeroes(c.ke_runtime_params);
    const rh = ke_runtime_create(f.ecs_h.ref, null, &rp, null);
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

fn parallelWorker(_: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) void {
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
}

test "disjoint systems in one wave run on more than one thread" {
    var f = try Fixture.init();
    defer f.deinit();

    var probe = ParallelProbe{};
    var slot_a = ParallelSlot{ .probe = &probe, .index = 0 };
    var slot_b = ParallelSlot{ .probe = &probe, .index = 1 };

    const acc_a = [_]c.ke_component_access{access(1, c.KE_ACCESS_WRITE)};
    const acc_b = [_]c.ke_component_access{access(2, c.KE_ACCESS_WRITE)};

    var sa = systemParams("SysA", c.KE_PHASE_UPDATE);
    sa.access_list = &acc_a;
    sa.access_count = 1;
    sa.user_data = &slot_a;
    sa.execute = &parallelWorker;
    try testing.expect(f.rt().register_system.?(f.rt(), &sa, null) != 0);

    var sb = systemParams("SysB", c.KE_PHASE_UPDATE);
    sb.access_list = &acc_b;
    sb.access_count = 1;
    sb.user_data = &slot_b;
    sb.execute = &parallelWorker;
    try testing.expect(f.rt().register_system.?(f.rt(), &sb, null) != 0);

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

fn orderWorker(_: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) void {
    const slot: *OrderSlot = @ptrCast(@alignCast(ud.?));
    const i = slot.probe.next.fetchAdd(1, .acq_rel);
    if (i < slot.probe.slots.len) slot.probe.slots[i].store(slot.tag, .release);
}

test "systems conflicting on a component run one after the other" {
    var f = try Fixture.init();
    defer f.deinit();

    var probe = OrderProbe{};
    var slot_1 = OrderSlot{ .probe = &probe, .tag = 1 };
    var slot_2 = OrderSlot{ .probe = &probe, .tag = 2 };

    const acc = [_]c.ke_component_access{access(42, c.KE_ACCESS_WRITE)};

    var s1 = systemParams("Writer1", c.KE_PHASE_UPDATE);
    s1.access_list = &acc;
    s1.access_count = 1;
    s1.user_data = &slot_1;
    s1.execute = &orderWorker;
    try testing.expect(f.rt().register_system.?(f.rt(), &s1, null) != 0);

    var s2 = systemParams("Writer2", c.KE_PHASE_UPDATE);
    s2.access_list = &acc;
    s2.access_count = 1;
    s2.user_data = &slot_2;
    s2.execute = &orderWorker;
    try testing.expect(f.rt().register_system.?(f.rt(), &s2, null) != 0);

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

    var fx = systemParams("FixedCounter", c.KE_PHASE_FIXED_UPDATE);
    fx.user_data = &fixed_ticks;
    fx.execute = &countingSystem;
    try testing.expect(f.rt().register_system.?(f.rt(), &fx, null) != 0);

    var up = systemParams("UpdateCounter", c.KE_PHASE_UPDATE);
    up.user_data = &update_ticks;
    up.execute = &countingSystem;
    try testing.expect(f.rt().register_system.?(f.rt(), &up, null) != 0);

    for (0..10) |_| try testing.expect(f.tick(1.0 / 60.0));

    try testing.expectEqual(@as(u32, 10), update_ticks.load(.acquire));
    try testing.expectEqual(@as(u32, 10), fixed_ticks.load(.acquire));
}

test "a large frame catches the fixed phase up" {
    var f = try Fixture.init();
    defer f.deinit();

    var fixed_ticks = Counter.init(0);
    var fx = systemParams("FixedCounter", c.KE_PHASE_FIXED_UPDATE);
    fx.user_data = &fixed_ticks;
    fx.execute = &countingSystem;
    try testing.expect(f.rt().register_system.?(f.rt(), &fx, null) != 0);

    try testing.expect(f.tick(5.0 / 60.0));
    try testing.expectEqual(@as(u32, 5), fixed_ticks.load(.acquire));
}

test "a frame shorter than the fixed step takes no step" {
    var f = try Fixture.init();
    defer f.deinit();

    var fixed_ticks = Counter.init(0);
    var fx = systemParams("FixedCounter", c.KE_PHASE_FIXED_UPDATE);
    fx.user_data = &fixed_ticks;
    fx.execute = &countingSystem;
    try testing.expect(f.rt().register_system.?(f.rt(), &fx, null) != 0);

    try testing.expect(f.tick(1.0 / 120.0));
    try testing.expectEqual(@as(u32, 0), fixed_ticks.load(.acquire));

    try testing.expect(f.tick(1.0 / 120.0));
    try testing.expectEqual(@as(u32, 1), fixed_ticks.load(.acquire));
}

test "a huge frame is capped so the fixed phase cannot spiral" {
    var f = try Fixture.init();
    defer f.deinit();

    var fixed_ticks = Counter.init(0);
    var fx = systemParams("FixedCounter", c.KE_PHASE_FIXED_UPDATE);
    fx.user_data = &fixed_ticks;
    fx.execute = &countingSystem;
    try testing.expect(f.rt().register_system.?(f.rt(), &fx, null) != 0);

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

fn gatedRenderBody(_: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) void {
    while (!g_gated_render_may_finish.load(.acquire)) std.atomic.spinLoopHint();
    _ = g_gated_render_runs.fetchAdd(1, .acq_rel);
}

test "tick dispatches the render phase without waiting for it" {
    var f = try Fixture.init();
    defer f.deinit();

    g_gated_render_runs.store(0, .release);
    g_gated_render_may_finish.store(false, .release);

    var rnd = systemParams("GatedRender", c.KE_PHASE_RENDER);
    rnd.execute = &gatedRenderBody;
    try testing.expect(f.rt().register_system.?(f.rt(), &rnd, null) != 0);

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

fn extractSimWriter(ctx: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) void {
    var seg_count: usize = 0;
    const segs = ke_system_ctx_view(ctx, 0, &seg_count);
    if (segs == null) return;
    for (0..seg_count) |s| {
        const col: [*]i32 = @ptrCast(@alignCast(segs[s].columns[0] orelse continue));
        for (0..segs[s].count) |i| col[i] = 42;
    }
}

fn extractRenderReader(ctx: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) void {
    var seg_count: usize = 0;
    const segs = ke_system_ctx_view(ctx, 0, &seg_count);
    if (segs != null and seg_count > 0 and segs[0].count > 0) {
        if (segs[0].columns[0]) |col| {
            const typed: [*]const i32 = @ptrCast(@alignCast(col));
            g_extract_probe.seen.store(typed[0], .release);
            g_extract_probe.seen_ptr.store(@intFromPtr(col), .release);
        }
    }
    _ = g_extract_probe.runs.fetchAdd(1, .acq_rel);
}

test "the render extract carries this tick's sim write" {
    var f = try Fixture.init();
    defer f.deinit();

    const cid = f.ecs().component_register.?(f.ecs(), "Extract.Value", @sizeOf(i32), null, 0, null);
    const e = f.ecs().entity_create.?(f.ecs());
    const v = f.ecs().component_add.?(f.ecs(), e, cid);
    try testing.expect(v != null);
    @as(*i32, @ptrCast(@alignCast(v.?))).* = 0;

    g_extract_probe.seen.store(-1, .release);
    g_extract_probe.seen_ptr.store(0, .release);
    g_extract_probe.runs.store(0, .release);

    var wq = std.mem.zeroes(c.ke_query_decl);
    wq.terms[0] = access(cid, c.KE_ACCESS_WRITE);
    wq.term_count = 1;

    var sim = systemParams("SimWriter", c.KE_PHASE_UPDATE);
    sim.queries = &wq;
    sim.query_count = 1;
    sim.execute = &extractSimWriter;
    try testing.expect(f.rt().register_system.?(f.rt(), &sim, null) != 0);

    var rq = std.mem.zeroes(c.ke_query_decl);
    rq.terms[0] = access(cid, c.KE_ACCESS_READ);
    rq.term_count = 1;

    var rnd = systemParams("RenderReader", c.KE_PHASE_RENDER);
    rnd.queries = &rq;
    rnd.query_count = 1;
    rnd.execute = &extractRenderReader;
    try testing.expect(f.rt().register_system.?(f.rt(), &rnd, null) != 0);

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

fn extractPosVelReader(ctx: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) void {
    var seg_count: usize = 0;
    const segs = ke_system_ctx_view(ctx, 0, &seg_count);
    if (segs != null) {
        for (0..seg_count) |s| {
            const pc: [*]const Vec3 = @ptrCast(@alignCast(segs[s].columns[0] orelse continue));
            const vc: [*]const Vec3 = @ptrCast(@alignCast(segs[s].columns[1] orelse continue));
            for (0..segs[s].count) |i| {
                g_extract_pv_sum += @as(f64, pc[i].x) + @as(f64, vc[i].x);
            }
        }
    }
    _ = g_extract_pv_runs.fetchAdd(1, .acq_rel);
}

test "the render extract keeps multi term columns aligned" {
    var f = try Fixture.init();
    defer f.deinit();

    const pos = f.ecs().component_register.?(f.ecs(), "ExtractPos", @sizeOf(Vec3), null, 0, null);
    const vel = f.ecs().component_register.?(f.ecs(), "ExtractVel", @sizeOf(Vec3), null, 0, null);

    var expect: f64 = 0.0;
    for (0..64) |i| {
        const e = f.ecs().entity_create.?(f.ecs());
        _ = f.ecs().component_add.?(f.ecs(), e, pos);
        _ = f.ecs().component_add.?(f.ecs(), e, vel);
        const p: *Vec3 = @ptrCast(@alignCast(f.ecs().component_get.?(f.ecs(), e, pos).?));
        const v: *Vec3 = @ptrCast(@alignCast(f.ecs().component_get.?(f.ecs(), e, vel).?));
        p.x = @floatFromInt(i);
        v.x = @floatFromInt(i * 2);
        expect += @as(f64, @floatFromInt(i)) + @as(f64, @floatFromInt(i * 2));
    }

    var rq = std.mem.zeroes(c.ke_query_decl);
    rq.terms[0] = access(pos, c.KE_ACCESS_READ);
    rq.terms[1] = access(vel, c.KE_ACCESS_READ);
    rq.term_count = 2;

    var rnd = systemParams("RenderPosVel", c.KE_PHASE_RENDER);
    rnd.queries = &rq;
    rnd.query_count = 1;
    rnd.execute = &extractPosVelReader;
    try testing.expect(f.rt().register_system.?(f.rt(), &rnd, null) != 0);

    g_extract_pv_sum = 0.0;
    g_extract_pv_runs.store(0, .release);

    try testing.expect(f.tick(1.0 / 60.0));
    f.flushRender();

    try testing.expect(g_extract_pv_runs.load(.acquire) >= 1);
    try testing.expectEqual(expect, g_extract_pv_sum);
}

fn waveSystem(list: [*c]const c.ke_component_access, count: u32) c.ke_runtime_system_params {
    var s = systemParams("Synthetic", c.KE_PHASE_UPDATE);
    s.access_list = list;
    s.access_count = count;
    s.execute = &noopSystem;
    return s;
}

test "no systems produce no waves" {
    var assignments = [_]u32{ 99, 99, 99, 99 };
    var wave_count: u32 = 99;
    ke_runtime_debug_compute_waves(null, 0, &assignments, &wave_count);
    try testing.expectEqual(@as(u32, 0), wave_count);
}

test "a single system occupies one wave" {
    const acc = [_]c.ke_component_access{access(1, c.KE_ACCESS_WRITE)};
    const sys = [_]c.ke_runtime_system_params{waveSystem(&acc, 1)};

    var assignments = [_]u32{99};
    var wave_count: u32 = 0;
    ke_runtime_debug_compute_waves(&sys, 1, &assignments, &wave_count);

    try testing.expectEqual(@as(u32, 1), wave_count);
    try testing.expectEqual(@as(u32, 0), assignments[0]);
}

test "systems writing different components share a wave" {
    const a = [_]c.ke_component_access{access(1, c.KE_ACCESS_WRITE)};
    const b = [_]c.ke_component_access{access(2, c.KE_ACCESS_WRITE)};
    const sys = [_]c.ke_runtime_system_params{ waveSystem(&a, 1), waveSystem(&b, 1) };

    var assignments = [_]u32{ 99, 99 };
    var wave_count: u32 = 0;
    ke_runtime_debug_compute_waves(&sys, 2, &assignments, &wave_count);

    try testing.expectEqual(@as(u32, 1), wave_count);
    try testing.expectEqual(@as(u32, 0), assignments[0]);
    try testing.expectEqual(@as(u32, 0), assignments[1]);
}

test "two systems writing the same component land in different waves" {
    const a = [_]c.ke_component_access{access(1, c.KE_ACCESS_WRITE)};
    const b = [_]c.ke_component_access{access(1, c.KE_ACCESS_WRITE)};
    const sys = [_]c.ke_runtime_system_params{ waveSystem(&a, 1), waveSystem(&b, 1) };

    var assignments = [_]u32{ 99, 99 };
    var wave_count: u32 = 0;
    ke_runtime_debug_compute_waves(&sys, 2, &assignments, &wave_count);

    try testing.expectEqual(@as(u32, 2), wave_count);
    try testing.expectEqual(@as(u32, 0), assignments[0]);
    try testing.expectEqual(@as(u32, 1), assignments[1]);
}

test "a writer and a reader of the same component land in different waves" {
    const a = [_]c.ke_component_access{access(5, c.KE_ACCESS_WRITE)};
    const b = [_]c.ke_component_access{access(5, c.KE_ACCESS_READ)};
    const sys = [_]c.ke_runtime_system_params{ waveSystem(&a, 1), waveSystem(&b, 1) };

    var assignments = [_]u32{ 99, 99 };
    var wave_count: u32 = 0;
    ke_runtime_debug_compute_waves(&sys, 2, &assignments, &wave_count);

    try testing.expectEqual(@as(u32, 2), wave_count);
}

test "two readers of the same component share a wave" {
    const a = [_]c.ke_component_access{access(7, c.KE_ACCESS_READ)};
    const b = [_]c.ke_component_access{access(7, c.KE_ACCESS_READ)};
    const sys = [_]c.ke_runtime_system_params{ waveSystem(&a, 1), waveSystem(&b, 1) };

    var assignments = [_]u32{ 99, 99 };
    var wave_count: u32 = 0;
    ke_runtime_debug_compute_waves(&sys, 2, &assignments, &wave_count);

    try testing.expectEqual(@as(u32, 1), wave_count);
    try testing.expectEqual(@as(u32, 0), assignments[0]);
    try testing.expectEqual(@as(u32, 0), assignments[1]);
}

test "a chain of conflicts groups greedily" {
    const a = [_]c.ke_component_access{access(1, c.KE_ACCESS_WRITE)};
    const b = [_]c.ke_component_access{access(1, c.KE_ACCESS_READ)};
    const d = [_]c.ke_component_access{access(2, c.KE_ACCESS_WRITE)};
    const e = [_]c.ke_component_access{access(2, c.KE_ACCESS_READ)};
    const sys = [_]c.ke_runtime_system_params{
        waveSystem(&a, 1),
        waveSystem(&b, 1),
        waveSystem(&d, 1),
        waveSystem(&e, 1),
    };

    var assignments = [_]u32{ 99, 99, 99, 99 };
    var wave_count: u32 = 0;
    ke_runtime_debug_compute_waves(&sys, 4, &assignments, &wave_count);

    try testing.expectEqual(@as(u32, 3), wave_count);
    try testing.expectEqual(@as(u32, 0), assignments[0]);
    try testing.expectEqual(@as(u32, 1), assignments[1]);
    try testing.expectEqual(@as(u32, 1), assignments[2]);
    try testing.expectEqual(@as(u32, 2), assignments[3]);
}

test "the clear shadow and cull access shape lands in one wave" {
    const clear = [_]c.ke_component_access{
        access(1, c.KE_ACCESS_READ),
        access(2, c.KE_ACCESS_WRITE),
    };
    const shadow = [_]c.ke_component_access{
        access(1, c.KE_ACCESS_READ),
        access(3, c.KE_ACCESS_READ),
        access(4, c.KE_ACCESS_WRITE),
    };
    const cull = [_]c.ke_component_access{
        access(1, c.KE_ACCESS_READ),
        access(3, c.KE_ACCESS_READ),
        access(5, c.KE_ACCESS_WRITE),
    };
    const sys = [_]c.ke_runtime_system_params{
        waveSystem(&clear, 2),
        waveSystem(&shadow, 3),
        waveSystem(&cull, 3),
    };

    var assignments = [_]u32{ 99, 99, 99 };
    var wave_count: u32 = 0;
    ke_runtime_debug_compute_waves(&sys, 3, &assignments, &wave_count);

    try testing.expectEqual(@as(u32, 1), wave_count);
    try testing.expectEqual(assignments[0], assignments[1]);
    try testing.expectEqual(assignments[1], assignments[2]);
}

const SpawnProbe = struct {
    ids: [3]c.ke_entity = .{ c.KE_ENTITY_INVALID, c.KE_ENTITY_INVALID, c.KE_ENTITY_INVALID },
    calls: Counter = Counter.init(0),
    cid: c.ke_component_id = 0,
};

fn spawnerBody(ctx: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) void {
    const probe: *SpawnProbe = @ptrCast(@alignCast(ud.?));
    for (&probe.ids) |*slot| slot.* = ke_system_ctx_spawn(ctx);
    _ = probe.calls.fetchAdd(1, .acq_rel);
}

test "a deferred spawn is applied at the wave barrier" {
    var f = try Fixture.init();
    defer f.deinit();

    ke_system_ctx_reset_defer_applied();

    var probe = SpawnProbe{};
    var sys = systemParams("Spawner", c.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &spawnerBody;
    try testing.expect(f.rt().register_system.?(f.rt(), &sys, null) != 0);

    try testing.expect(f.tick(1.0 / 60.0));
    try testing.expectEqual(@as(u32, 1), probe.calls.load(.acquire));
    try testing.expectEqual(@as(u32, 3), ke_system_ctx_defer_applied_count());
}

test "spawn hands the system body an id it can actually use" {
    var f = try Fixture.init();
    defer f.deinit();

    var probe = SpawnProbe{};
    var sys = systemParams("Spawner", c.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &spawnerBody;
    try testing.expect(f.rt().register_system.?(f.rt(), &sys, null) != 0);
    try testing.expect(f.tick(1.0 / 60.0));

    const e = f.ecs();
    const cid = e.component_register.?(e, "spawned_probe", 4, null, 0, null);
    for (probe.ids, 0..) |id, i| {
        try testing.expect(id != c.KE_ENTITY_INVALID);
        for (probe.ids[i + 1 ..]) |other| try testing.expect(id != other);
        try testing.expect(e.component_add.?(e, id, cid) != null);
    }
}

test "an entity spawned with no components still exists after the barrier" {
    var f = try Fixture.init();
    defer f.deinit();

    var probe = SpawnProbe{};
    var sys = systemParams("Spawner", c.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &spawnerBody;
    try testing.expect(f.rt().register_system.?(f.rt(), &sys, null) != 0);
    try testing.expect(f.tick(1.0 / 60.0));

    const e = f.ecs();
    const cid = e.component_register.?(e, "exists_probe", 4, null, 0, null);
    e.entity_destroy.?(e, probe.ids[0]);
    try testing.expect(e.component_add.?(e, probe.ids[0], cid) == null);
}

const MutatorProbe = struct {
    payload: u8 = 'X',
    ok: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

fn mutatorBody(ctx: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32) callconv(.c) void {
    const probe: *MutatorProbe = @ptrCast(@alignCast(ud.?));
    const attached = ke_system_ctx_attach(ctx, 42, 5, &probe.payload, 1);
    const detached = ke_system_ctx_detach(ctx, 42, 5);
    const despawned = ke_system_ctx_despawn(ctx, 42);
    probe.ok.store(attached and detached and despawned, .release);
}

test "deferred attach detach and despawn are applied at the barrier" {
    var f = try Fixture.init();
    defer f.deinit();

    ke_system_ctx_reset_defer_applied();

    var probe = MutatorProbe{};
    var sys = systemParams("Mutator", c.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &mutatorBody;
    try testing.expect(f.rt().register_system.?(f.rt(), &sys, null) != 0);

    try testing.expect(f.tick(1.0 / 60.0));
    try testing.expect(probe.ok.load(.acquire));
    try testing.expectEqual(@as(u32, 3), ke_system_ctx_defer_applied_count());
}

fn repeatSpawnerBody(ctx: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) void {
    _ = ke_system_ctx_spawn(ctx);
}

test "the defer queue drains between ticks" {
    var f = try Fixture.init();
    defer f.deinit();

    ke_system_ctx_reset_defer_applied();

    var sys = systemParams("RepeatSpawner", c.KE_PHASE_UPDATE);
    sys.execute = &repeatSpawnerBody;
    try testing.expect(f.rt().register_system.?(f.rt(), &sys, null) != 0);

    for (0..5) |_| try testing.expect(f.tick(1.0 / 60.0));

    try testing.expectEqual(@as(u32, 5), ke_system_ctx_defer_applied_count());
}

test "a zero size component registers as a usable tag" {
    const h = ke_ecs_flecs_create(null, null);
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    const ecs: *c.ke_ecs = @ptrCast(h.ref);

    var tag = ecs.component_register.?(ecs, "ZeroSizeTag", 0, null, 0, null);
    try testing.expect(tag != 0);

    const e = ecs.entity_create.?(ecs);
    _ = ecs.component_add.?(ecs, e, tag);

    const q = ecs.query_register.?(ecs, &tag, 1);
    try testing.expect(q != c.KE_QUERY_INVALID);

    var segs = std.mem.zeroes([8]c.ke_ecs_segment);
    var seg_count: usize = 0;
    ecs.query_resolve.?(ecs, q, &segs, 8, &seg_count);

    var total: usize = 0;
    for (0..seg_count) |i| total += segs[i].count;
    try testing.expectEqual(@as(usize, 1), total);
}

fn parallelReaderBody(ctx: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) void {
    var seg_count: usize = 0;
    const segs = ke_system_ctx_view(ctx, 0, &seg_count);
    if (segs == null) return;

    var sink: f32 = 0.0;
    for (0..seg_count) |s| {
        const col: [*]const Vec3 = @ptrCast(@alignCast(segs[s].columns[0] orelse continue));
        for (0..segs[s].count) |i| sink += col[i].x;
    }
    std.mem.doNotOptimizeAway(sink);
}

test "two readers sharing a wave read the same storage without conflicting" {
    var f = try Fixture.init();
    defer f.deinit();

    const pos = f.ecs().component_register.?(f.ecs(), "pos", @sizeOf(Vec3), null, 0, null);
    try testing.expect(pos != 0);

    for (0..512) |i| {
        const e = f.ecs().entity_create.?(f.ecs());
        const p: *Vec3 = @ptrCast(@alignCast(f.ecs().component_add.?(f.ecs(), e, pos).?));
        p.x = @floatFromInt(i);
        p.y = 0.0;
        p.z = 0.0;
    }

    var read_pos = std.mem.zeroes(c.ke_query_decl);
    read_pos.terms[0] = access(pos, c.KE_ACCESS_READ);
    read_pos.term_count = 1;

    var a = systemParams("ReaderA", c.KE_PHASE_UPDATE);
    a.queries = &read_pos;
    a.query_count = 1;
    a.execute = &parallelReaderBody;

    var b = a;
    b.name = "ReaderB";

    try testing.expect(f.rt().register_system.?(f.rt(), &a, null) != 0);
    try testing.expect(f.rt().register_system.?(f.rt(), &b, null) != 0);

    const sysz = [_]c.ke_runtime_system_params{ a, b };
    var waves = [_]u32{ 0, 0 };
    var wave_count: u32 = 0;
    ke_runtime_debug_compute_waves(&sysz, 2, &waves, &wave_count);
    try testing.expectEqual(waves[0], waves[1]);

    for (0..300) |_| try testing.expect(f.tick(1.0 / 60.0));
}

var g_pv_sum: f64 = 0.0;

fn posVelBody(ctx: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) void {
    var seg_count: usize = 0;
    const segs = ke_system_ctx_view(ctx, 0, &seg_count);
    if (segs == null) return;
    for (0..seg_count) |s| {
        const pc: [*]const Vec3 = @ptrCast(@alignCast(segs[s].columns[0] orelse continue));
        const vc: [*]const Vec3 = @ptrCast(@alignCast(segs[s].columns[1] orelse continue));
        for (0..segs[s].count) |i| g_pv_sum += @as(f64, pc[i].x) + @as(f64, vc[i].x);
    }
}

test "a multi term query hands back aligned columns" {
    var f = try Fixture.init();
    defer f.deinit();

    const pos = f.ecs().component_register.?(f.ecs(), "pos2", @sizeOf(Vec3), null, 0, null);
    const vel = f.ecs().component_register.?(f.ecs(), "vel2", @sizeOf(Vec3), null, 0, null);
    try testing.expect(pos != 0);
    try testing.expect(vel != 0);

    var expect: f64 = 0.0;
    for (0..100) |i| {
        const e = f.ecs().entity_create.?(f.ecs());
        _ = f.ecs().component_add.?(f.ecs(), e, pos);
        _ = f.ecs().component_add.?(f.ecs(), e, vel);
        const p: *Vec3 = @ptrCast(@alignCast(f.ecs().component_get.?(f.ecs(), e, pos).?));
        const v: *Vec3 = @ptrCast(@alignCast(f.ecs().component_get.?(f.ecs(), e, vel).?));
        p.x = @floatFromInt(i);
        v.x = @floatFromInt(i * 2);
        expect += @as(f64, @floatFromInt(i)) + @as(f64, @floatFromInt(i * 2));
    }

    var q = std.mem.zeroes(c.ke_query_decl);
    q.terms[0] = access(pos, c.KE_ACCESS_READ);
    q.terms[1] = access(vel, c.KE_ACCESS_READ);
    q.term_count = 2;

    var s = systemParams("PosVel", c.KE_PHASE_UPDATE);
    s.queries = &q;
    s.query_count = 1;
    s.execute = &posVelBody;
    try testing.expect(f.rt().register_system.?(f.rt(), &s, null) != 0);

    g_pv_sum = 0.0;
    try testing.expect(f.tick(1.0 / 60.0));
    try testing.expectEqual(expect, g_pv_sum);
}
