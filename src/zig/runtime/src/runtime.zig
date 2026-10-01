const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

const c = @cImport({
    @cInclude("kernel_engine/runtime/runtime_create.h");
    @cInclude("kernel_engine/runtime/system_ctx.h");
});

const E = @import("kerror").Errors(c);

const KE_MAX_QUERIES_PER_SYSTEM = 8;
const KE_MAX_SEGMENTS_PER_QUERY = 32;
const KE_RUNTIME_PHASE_COUNT = 7;
const MAX_TERMS = c.KE_QUERY_MAX_TERMS;

const ACCESS_WRITE: c_uint = @intCast(c.KE_ACCESS_WRITE);

const heap = @import("heap");

fn cAlloc(comptime T: type, n: usize) ?[*]T {
    if (n == 0) return null;
    const slice = heap.gpa.alloc(T, n) catch return null;
    return slice.ptr;
}

fn cFree(comptime T: type, p: ?[*]T, n: usize) void {
    if (p) |pp| heap.gpa.free(pp[0..n]);
}

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

fn commandsOf(ptr: ?*c.ke_ecs_commands) ?*CtxState {
    const cmds = ptr orelse return null;
    return @ptrCast(@alignCast(cmds.handle));
}

fn bindCtx(ctx: *c.ke_system_ctx, commands: *c.ke_ecs_commands, state: *CtxState) void {
    commands.* = .{
        .handle = state,
        .spawn = &commandsSpawn,
        .attach = &commandsAttach,
        .detach = &commandsDetach,
        .despawn = &commandsDespawn,
        .@"defer" = &commandsDefer,
    };
    ctx.commands = commands;
    ctx.handle = state;
    ctx.view = &ctxView;
    ctx.slice = &ctxSlice;
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

fn debugComputeWaves(
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

fn ctxView(ctx: ?*c.ke_system_ctx, query_index: u32, out_count: [*c]usize) callconv(.c) [*c]const c.ke_ecs_segment {
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

fn ctxSlice(ctx: ?*c.ke_system_ctx, out_index: [*c]u32, out_count: [*c]u32) callconv(.c) void {
    const s = ctxOf(ctx);
    if (out_index != null) out_index.* = if (s) |st| st.slice_index else 0;
    if (out_count != null) out_count.* = if (s) |st| st.slice_count else 1;
}

fn recordTarget(self: ?*c.ke_ecs_commands, out_error: [*c][*c]c.ke_error, src: std.builtin.SourceLocation) ?*DeferQueue {
    const s = commandsOf(self) orelse {
        E.fail(out_error, .invalid_argument, "invalid command queue", src);
        return null;
    };
    return s.defer_q orelse {
        E.fail(out_error, .not_supported, "this phase may not change structure", src);
        return null;
    };
}

fn recordCommand(q: *DeferQueue, out_error: [*c][*c]c.ke_error, src: std.builtin.SourceLocation) ?*DeferCommand {
    if (!deferReserve(q, q.count + 1)) {
        E.fail(out_error, .out_of_memory, "command queue is full", src);
        return null;
    }
    const cmd = &q.cmds.?[q.count];
    q.count += 1;
    return cmd;
}

fn commandsSpawn(self: ?*c.ke_ecs_commands, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_entity {
    const q = recordTarget(self, out_error, @src()) orelse return c.KE_ENTITY_INVALID;
    const ecs = commandsOf(self).?.ecs orelse {
        E.fail(out_error, .not_initialized, "no world", @src());
        return c.KE_ENTITY_INVALID;
    };
    const entity = ecs.entity_reserve.?(ecs);
    if (entity == c.KE_ENTITY_INVALID) {
        E.fail(out_error, .out_of_memory, "entity id could not be reserved", @src());
        return c.KE_ENTITY_INVALID;
    }
    const cmd = recordCommand(q, out_error, @src()) orelse return c.KE_ENTITY_INVALID;
    cmd.kind = .spawn;
    cmd.entity = entity;
    return entity;
}

fn commandsAttach(self: ?*c.ke_ecs_commands, entity: c.ke_entity, cid: c.ke_component_id, data: ?*const anyopaque, size: usize, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const q = recordTarget(self, out_error, @src()) orelse return false;
    if (size != 0) {
        const ecs = commandsOf(self).?.ecs orelse {
            E.fail(out_error, .not_initialized, "no world", @src());
            return false;
        };
        if (size != ecs.component_size.?(ecs, cid)) {
            E.fail(out_error, .invalid_argument, "payload size differs from the component size", @src());
            return false;
        }
    }
    const offset = deferArenaPush(q, data, size);
    if (offset == std.math.maxInt(usize)) {
        E.fail(out_error, .out_of_memory, "command payload does not fit", @src());
        return false;
    }
    const cmd = recordCommand(q, out_error, @src()) orelse return false;
    cmd.kind = .attach;
    cmd.entity = entity;
    cmd.cid = cid;
    cmd.attach_offset = offset;
    cmd.attach_size = size;
    return true;
}

fn commandsDetach(self: ?*c.ke_ecs_commands, entity: c.ke_entity, cid: c.ke_component_id, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const q = recordTarget(self, out_error, @src()) orelse return false;
    const cmd = recordCommand(q, out_error, @src()) orelse return false;
    cmd.kind = .detach;
    cmd.entity = entity;
    cmd.cid = cid;
    return true;
}

fn commandsDespawn(self: ?*c.ke_ecs_commands, entity: c.ke_entity, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const q = recordTarget(self, out_error, @src()) orelse return false;
    const cmd = recordCommand(q, out_error, @src()) orelse return false;
    cmd.kind = .despawn;
    cmd.entity = entity;
    return true;
}

fn commandsDefer(self: ?*c.ke_ecs_commands, func: c.ke_defer_fn, user: ?*const anyopaque, user_size: usize, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const q = recordTarget(self, out_error, @src()) orelse return false;
    if (func == null) {
        E.fail(out_error, .invalid_argument, "no function to defer", @src());
        return false;
    }
    const offset = deferArenaPush(q, user, user_size);
    if (offset == std.math.maxInt(usize)) {
        E.fail(out_error, .out_of_memory, "command payload does not fit", @src());
        return false;
    }
    const cmd = recordCommand(q, out_error, @src()) orelse return false;
    cmd.kind = .callback;
    cmd.fn_ = func;
    cmd.attach_offset = offset;
    cmd.attach_size = user_size;
    return true;
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

fn deferAppliedCount() u32 {
    return s_defer_applied_total;
}
fn resetDeferApplied() void {
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
    name_storage: ?[]u8,
    access_storage: ?[]c.ke_component_access,
};

fn releaseSystem(rs: *RegisteredSystem) void {
    if (rs.name_storage) |n| heap.gpa.free(n);
    if (rs.access_storage) |a| heap.gpa.free(a);
    if (rs.seg_storage) |ss| cFree(c.ke_ecs_segment, ss, KE_MAX_QUERIES_PER_SYSTEM * KE_MAX_SEGMENTS_PER_QUERY);
    cFree(RegisteredSystem, @ptrCast(rs), 1);
}

const RegisteredModule = struct {
    user_data: ?*anyopaque,
    on_unload: c.ke_module_unload_fn,
};

const RenderJob = struct {
    h: *RuntimeHandle,
    dt: f32,
    failure: PhaseFailure = .{},
};

const RuntimeState = struct {
    ecs: *c.ke_ecs,
    scheduler: *c.ke_scheduler,
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

    if (h.state.module_count == h.state.module_capacity) {
        const new_cap: usize = if (h.state.module_capacity != 0) h.state.module_capacity * 2 else 4;
        const new_buf = cAlloc(RegisteredModule, new_cap) orelse {
            E.fail(out_error, .out_of_memory, "module array allocation failed", @src());
            return 0;
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
    if (!p.*.on_load.?(self, p.*.user_data, out_error)) {
        h.state.modules.?[slot] = .{ .user_data = null, .on_unload = null };
        return 0;
    }
    return id;
}

fn mergeAccess(rs: *RegisteredSystem, want: c.ke_component_access) bool {
    for (0..rs.derived_access_count) |d| {
        if (rs.derived_access[d].cid == want.cid) {
            rs.derived_access[d].access |= want.access;
            return true;
        }
    }
    if (rs.derived_access_count == rs.derived_access.len) return false;
    rs.derived_access[rs.derived_access_count] = want;
    rs.derived_access_count += 1;
    return true;
}

fn refuseAccess(rs: *RegisteredSystem, out_error: [*c][*c]c.ke_error) c.ke_system_id {
    releaseSystem(rs);
    E.fail(out_error, .invalid_argument, "system declares more distinct components than it can track", @src());
    return 0;
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

    if (p.*.query_count > KE_MAX_QUERIES_PER_SYSTEM) {
        E.fail(out_error, .invalid_argument, "system declares more queries than a system can hold", @src());
        return 0;
    }
    if (p.*.queries != null) {
        for (0..p.*.query_count) |q| {
            if (p.*.queries[q].term_count > MAX_TERMS) {
                E.fail(out_error, .invalid_argument, "query declares more terms than a query can hold", @src());
                return 0;
            }
        }
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
    rs.params = p.*;
    rs.query_count = 0;
    rs.seg_storage = null;
    rs.derived_access_count = 0;
    rs.name_storage = null;
    rs.access_storage = null;
    @memset(std.mem.asBytes(&rs.extracted), 0);

    if (p.*.name != null) {
        const text = std.mem.span(p.*.name);
        const copy = heap.gpa.alloc(u8, text.len + 1) catch {
            releaseSystem(rs);
            E.fail(out_error, .out_of_memory, "system name allocation failed", @src());
            return 0;
        };
        @memcpy(copy[0..text.len], text);
        copy[text.len] = 0;
        rs.name_storage = copy;
        rs.params.name = @ptrCast(copy.ptr);
    }

    if (p.*.queries != null and p.*.query_count > 0) {
        const qn = p.*.query_count;

        for (0..qn) |q| {
            const qd = &p.*.queries[q];
            rs.query_decls[q] = qd.*;
            rs.query_ids[q] = c.KE_QUERY_INVALID;
            for (0..qd.term_count) |t| {
                if (!mergeAccess(rs, qd.terms[t])) return refuseAccess(rs, out_error);
            }
        }
        rs.query_count = qn;

        for (0..p.*.access_count) |i| {
            if (!mergeAccess(rs, p.*.access_list[i])) return refuseAccess(rs, out_error);
        }

        rs.params.access_list = &rs.derived_access;
        rs.params.access_count = rs.derived_access_count;
        rs.params.queries = null;
        rs.params.query_count = 0;

        rs.seg_storage = cAlloc(c.ke_ecs_segment, KE_MAX_QUERIES_PER_SYSTEM * KE_MAX_SEGMENTS_PER_QUERY) orelse {
            releaseSystem(rs);
            E.fail(out_error, .out_of_memory, "query segment storage allocation failed", @src());
            return 0;
        };
    } else if (p.*.access_list != null and p.*.access_count > 0) {
        const copy = heap.gpa.alloc(c.ke_component_access, p.*.access_count) catch {
            releaseSystem(rs);
            E.fail(out_error, .out_of_memory, "system access list allocation failed", @src());
            return 0;
        };
        @memcpy(copy, p.*.access_list[0..p.*.access_count]);
        rs.access_storage = copy;
        rs.params.access_list = copy.ptr;
    }

    h.state.systems.?[h.state.system_count] = rs;
    h.state.system_count += 1;

    h.state.next_system_id += 1;
    return h.state.next_system_id;
}

const TaskPkg = struct {
    state: CtxState,
    ctx: c.ke_system_ctx,
    commands: c.ke_ecs_commands,
    execute: ?*const fn (?*c.ke_system_ctx, ?*anyopaque, f32, [*c][*c]c.ke_error) callconv(.c) bool,
    user_data: ?*anyopaque,
    dt: f32,
    defer_q: DeferQueue,
    allow_defer: bool,
};

const PhaseFailure = struct {
    type: ?*const c.ke_error_type = null,
    system: [*c]const u8 = null,

    fn firstOf(self: PhaseFailure, other: PhaseFailure) PhaseFailure {
        return if (self.type != null) self else other;
    }
};

fn taskPkgRun(data: ?*anyopaque, out_failure: [*c][*c]const c.ke_error_type) callconv(.c) void {
    const pkg: *TaskPkg = @ptrCast(@alignCast(data.?));
    if (pkg.allow_defer) pkg.state.defer_q = &pkg.defer_q;
    var err: [*c]c.ke_error = null;
    if (pkg.execute.?(&pkg.ctx, pkg.user_data, pkg.dt, &err)) return;
    if (out_failure == null) return;
    out_failure.* = if (err != null and err.*.type != null)
        err.*.type
    else
        E.typeOf(.general);
}

const WaveRunCtx = struct {
    h: *RuntimeHandle,
    pkgs: [*]TaskPkg,
    tasks: [*]?*c.ke_task,
    pinned: [*]u32,
    wave_size: u32,
};

fn runWaveBody(wc: *WaveRunCtx) PhaseFailure {
    const sched = wc.h.state.scheduler;
    var t: u32 = 0;
    while (t < wc.wave_size) : (t += 1) {
        if (wc.pinned[t] > 0)
            wc.tasks[t] = sched.dispatch_pinned.?(sched, wc.pinned[t], taskPkgRun, &wc.pkgs[t])
        else
            wc.tasks[t] = sched.dispatch.?(sched, taskPkgRun, &wc.pkgs[t]);
    }
    var failure = PhaseFailure{};
    t = 0;
    while (t < wc.wave_size) : (t += 1) {
        var err: [*c]c.ke_error = null;
        if (sched.wait.?(sched, wc.tasks[t], &err)) continue;
        if (failure.type != null) continue;
        failure = .{
            .type = if (err != null and err.*.type != null) err.*.type else E.typeOf(.general),
            .system = wc.pkgs[t].state.system_name,
        };
    }
    return failure;
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

fn segmentOverflow(rs: *const RegisteredSystem) PhaseFailure {
    return .{ .type = E.typeOf(.out_of_memory), .system = rs.params.name };
}

fn runtimeRunPhase(h: *RuntimeHandle, phase: c.ke_phase, dt: f32) PhaseFailure {
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
    var wave_count: u32 = 0;
    debugComputeWaves(phase_params, phase_count, wave_assignments, &wave_count);

    const pkgs = (h.state.phase_pkgs orelse return .{}) + base;
    const tasks = (h.state.phase_tasks orelse return .{}) + base;
    const pinned = (h.state.phase_pinned orelse return .{}) + base;

    var failure = PhaseFailure{};
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
                        if (cnt > KE_MAX_SEGMENTS_PER_QUERY) return segmentOverflow(rs);
                        rs.seg_counts[q] = cnt;
                    }
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
        failure = failure.firstOf(runWaveBody(&wc));

        var t: u32 = 0;
        while (t < wave_size) : (t += 1) {
            deferFlush(&pkgs[t].defer_q, h.state.ecs);
            if (pkgs[t].defer_q.cmds) |cmds| cFree(DeferCommand, cmds, pkgs[t].defer_q.capacity);
            if (pkgs[t].defer_q.arena) |arena| cFree(u8, arena, pkgs[t].defer_q.arena_capacity);
        }

        if (failure.type != null) break;
    }
    return failure;
}

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

fn runtimeExtractRenderState(h: *RuntimeHandle) PhaseFailure {
    if (h.state.ecs.query_resolve == null) return .{};
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
            if (raw_count > KE_MAX_SEGMENTS_PER_QUERY) return segmentOverflow(rs);

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
                        const new_col = cAllocBytes(eq.col_elem_size[t] *% new_cap) orelse return segmentOverflow(rs);
                        if (eq.col_bufs[t]) |oldc| cFreeBytes(oldc, eq.col_elem_size[t] *% eq.capacity);
                        eq.col_bufs[t] = new_col;
                    }
                    eq.capacity = new_cap;
                }
                if (total > eq.capacity) return segmentOverflow(rs);
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
    return .{};
}

fn renderJobRun(data: ?*anyopaque, out_failure: [*c][*c]const c.ke_error_type) callconv(.c) void {
    const job: *RenderJob = @ptrCast(@alignCast(data.?));
    job.failure = runtimeRunPhase(job.h, c.KE_PHASE_RENDER, job.dt);
    if (job.failure.type) |t| {
        if (out_failure != null) out_failure.* = t;
    }
}

fn runtimeJoinPendingRender(h: *RuntimeHandle) PhaseFailure {
    const task = h.state.pending_render_task orelse return .{};
    _ = h.state.scheduler.wait.?(h.state.scheduler, task, null);
    h.state.pending_render_task = null;
    const job = h.state.render_job orelse return .{};
    const failure = job.failure;
    job.failure = .{};
    return failure;
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
    var failure = PhaseFailure{};
    if (!h.state.started) {
        h.state.started = true;
        failure = runtimeRunPhase(h, c.KE_PHASE_STARTUP, 0.0);
    }
    if (failure.type == null) failure = runtimeRunPhase(h, c.KE_PHASE_PRE_UPDATE, dt);

    h.state.fixed_accumulator += dt;
    if (h.state.fixed_accumulator > h.state.fixed_dt_max_accum) {
        h.state.fixed_accumulator = h.state.fixed_dt_max_accum;
    }
    while (failure.type == null and h.state.fixed_accumulator >= h.state.fixed_dt) {
        failure = runtimeRunPhase(h, c.KE_PHASE_FIXED_UPDATE, h.state.fixed_dt);
        h.state.fixed_accumulator -= h.state.fixed_dt;
    }

    if (failure.type == null) failure = runtimeRunPhase(h, c.KE_PHASE_UPDATE, dt);
    if (failure.type == null) failure = runtimeRunPhase(h, c.KE_PHASE_POST_UPDATE, dt);

    failure = runtimeJoinPendingRender(h).firstOf(failure);
    if (failure.type) |t| {
        E.failWithType(out_error, t, failure.system orelse "system body failed", @src());
        return false;
    }

    failure = runtimeExtractRenderState(h);
    if (failure.type) |t| {
        E.failWithType(out_error, t, failure.system orelse "render extraction failed", @src());
        return false;
    }

    if (h.state.render_job == null) {
        if (cAlloc(RenderJob, 1)) |rj| h.state.render_job = &rj[0];
    }
    if (h.state.render_job) |job| {
        job.h = h;
        job.dt = dt;
        job.failure = .{};
        h.state.pending_render_task = h.state.scheduler.dispatch.?(h.state.scheduler, renderJobRun, job);
    } else {
        failure = runtimeRunPhase(h, c.KE_PHASE_RENDER, dt);
        if (failure.type) |t| {
            E.failWithType(out_error, t, failure.system orelse "system body failed", @src());
            return false;
        }
    }

    return true;
}

fn runtimeFlushRender(self: ?*c.ke_runtime, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    if (self == null or self.?.handle == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const failure = runtimeJoinPendingRender(handleOf(self.?));
    if (failure.type) |t| {
        E.failWithType(out_error, t, failure.system orelse "system body failed", @src());
        return false;
    }
    return true;
}

fn runtimeDestroy(self: ?*c.ke_runtime) callconv(.c) void {
    if (self == null or self.?.handle == null) return;
    const h = handleOf(self.?);

    _ = runtimeJoinPendingRender(h);

    if (h.state.started) _ = runtimeRunPhase(h, c.KE_PHASE_SHUTDOWN, 0.0);

    if (h.state.modules) |modules| {
        var i = h.state.module_count;
        while (i > 0) {
            i -= 1;
            if (modules[i].on_unload) |unload| unload(self, modules[i].user_data);
        }
        cFree(RegisteredModule, modules, h.state.module_capacity);
    }

    if (h.state.render_job) |rj| cFree(RenderJob, @ptrCast(rj), 1);

    if (h.state.systems) |systems| {
        for (0..h.state.system_count) |i| {
            const rs = systems[i].?;
            for (0..KE_MAX_QUERIES_PER_SYSTEM) |q| {
                const eq = &rs.extracted[q];
                if (eq.entities_buf) |eb| cFree(c.ke_entity, eb, eq.capacity);
                for (0..MAX_TERMS) |t| {
                    if (eq.col_bufs[t]) |cb| cFreeBytes(cb, eq.col_elem_size[t] *% eq.capacity);
                }
            }
            releaseSystem(rs);
        }
        cFree(?*RegisteredSystem, systems, h.state.system_capacity);
    }
    freePhaseScratch(h);
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
        _ = self.rt().flush_render.?(self.rt(), null);
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

fn noopSystem(_: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    return true;
}

fn refusingSystem(_: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    E.fail(out_error, .not_supported, "body refused", @src());
    return false;
}

const Counter = std.atomic.Value(u32);

fn countingSystem(_: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const counter: *Counter = @ptrCast(@alignCast(ud.?));
    _ = counter.fetchAdd(1, .acq_rel);
    return true;
}

const ModuleCtx = struct {
    load_calls: Counter = Counter.init(0),
    system_ticks: Counter = Counter.init(0),
};

fn moduleTickSystem(_: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const ctx: *ModuleCtx = @ptrCast(@alignCast(ud.?));
    _ = ctx.system_ticks.fetchAdd(1, .acq_rel);
    return true;
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

const UnloadRecorder = struct {
    seen: [4]u32 = [_]u32{0} ** 4,
    count: usize = 0,
};

const OrderedModule = struct {
    recorder: *UnloadRecorder,
    tag: u32,
};

fn orderedOnLoad(_: ?*c.ke_runtime, _: ?*anyopaque, _: [*c][*c]c.ke_error) callconv(.c) bool {
    return true;
}

fn refusingOnLoad(_: ?*c.ke_runtime, _: ?*anyopaque, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    E.fail(out_error, .invalid_argument, "module refused to load", @src());
    return false;
}

fn orderedOnUnload(_: ?*c.ke_runtime, ud: ?*anyopaque) callconv(.c) void {
    const m: *OrderedModule = @ptrCast(@alignCast(ud.?));
    m.recorder.seen[m.recorder.count] = m.tag;
    m.recorder.count += 1;
}

const SliceProbe = struct {
    calls: Counter = Counter.init(0),
    seen: [64]Counter = [_]Counter{Counter.init(0)} ** 64,
    reported_count: Counter = Counter.init(0),
};

fn sliceProbeSystem(ctx: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const probe: *SliceProbe = @ptrCast(@alignCast(ud.?));
    var index: u32 = 99;
    var count: u32 = 99;
    ctx.?.slice.?(ctx, &index, &count);
    _ = probe.calls.fetchAdd(1, .acq_rel);
    probe.reported_count.store(count, .release);
    if (index < probe.seen.len) _ = probe.seen[index].fetchAdd(1, .acq_rel);
    return true;
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

test "a module's unload hook runs when the runtime is destroyed" {
    var recorder = UnloadRecorder{};
    var only = OrderedModule{ .recorder = &recorder, .tag = 7 };

    var f = try Fixture.init();
    var mod = std.mem.zeroes(c.ke_runtime_module_params);
    mod.name = "UnloadModule";
    mod.user_data = &only;
    mod.on_load = &orderedOnLoad;
    mod.on_unload = &orderedOnUnload;

    try testing.expect(f.rt().register_module.?(f.rt(), &mod, null) != 0);
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
        var mod = std.mem.zeroes(c.ke_runtime_module_params);
        mod.name = "Ordered";
        mod.user_data = m;
        mod.on_load = &orderedOnLoad;
        mod.on_unload = &orderedOnUnload;
        try testing.expect(f.rt().register_module.?(f.rt(), &mod, null) != 0);
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

    var good = std.mem.zeroes(c.ke_runtime_module_params);
    good.name = "Loads";
    good.user_data = &loaded;
    good.on_load = &orderedOnLoad;
    good.on_unload = &orderedOnUnload;
    try testing.expect(f.rt().register_module.?(f.rt(), &good, null) != 0);

    var bad = std.mem.zeroes(c.ke_runtime_module_params);
    bad.name = "Refuses";
    bad.user_data = &refused;
    bad.on_load = &refusingOnLoad;
    bad.on_unload = &orderedOnUnload;
    try testing.expectEqual(@as(c.ke_module_id, 0), f.rt().register_module.?(f.rt(), &bad, null));

    f.deinit();

    try testing.expectEqual(@as(usize, 1), recorder.count);
    try testing.expectEqual(@as(u32, 1), recorder.seen[0]);
}

test "registering a module with no params is refused" {
    var f = try Fixture.init();
    defer f.deinit();

    try testing.expectEqual(@as(c.ke_module_id, 0), f.rt().register_module.?(f.rt(), null, null));
}

test "a body that fails the tick keeps the later phases from running" {
    var f = try Fixture.init();
    defer f.deinit();

    var counter = Counter.init(0);

    var boom = systemParams("Boom", c.KE_PHASE_PRE_UPDATE);
    boom.execute = &refusingSystem;
    try testing.expect(f.rt().register_system.?(f.rt(), &boom, null) != 0);

    var later = systemParams("Later", c.KE_PHASE_POST_UPDATE);
    later.execute = &countingSystem;
    later.user_data = &counter;
    try testing.expect(f.rt().register_system.?(f.rt(), &later, null) != 0);

    var err: [*c]c.ke_error = null;
    try testing.expect(!f.rt().tick.?(f.rt(), 1.0 / 60.0, &err));
    try testing.expect(err != null);
    try testing.expectEqualStrings("ke.error.not_supported", std.mem.span(err.*.type.*.name));
    try testing.expectEqualStrings("Boom", std.mem.span(err.*.message));
    try testing.expectEqual(@as(u32, 0), counter.load(.acquire));
}

test "registering a system with no execute body is refused" {
    var f = try Fixture.init();
    defer f.deinit();

    const sys = systemParams("Bad", c.KE_PHASE_UPDATE);
    try testing.expectEqual(@as(c.ke_system_id, 0), f.rt().register_system.?(f.rt(), &sys, null));
}

const BareRuntime = struct {
    ecs: c.ke_ecs = std.mem.zeroes(c.ke_ecs),
    scheduler: c.ke_scheduler = std.mem.zeroes(c.ke_scheduler),
    runtime_h: c.ke_runtime_handle = undefined,

    fn init(self: *BareRuntime) !void {
        var rp = std.mem.zeroes(c.ke_runtime_params);
        self.runtime_h = ke_runtime_create(&self.ecs, &self.scheduler, &rp, null);
        try testing.expect(self.runtime_h.ref != null);
    }

    fn deinit(self: *BareRuntime) void {
        self.runtime_h.destroy.?(self.runtime_h.ref.?);
    }

    fn rt(self: *BareRuntime) *c.ke_runtime {
        return @ptrCast(self.runtime_h.ref);
    }

    fn registered(self: *BareRuntime, index: usize) *RegisteredSystem {
        return handleOf(self.rt()).state.systems.?[index].?;
    }
};

fn noopBody(_: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    return true;
}

fn scribble(bytes: []u8) void {
    @memset(bytes, 'X');
}

test "a registered system keeps its own copy of the name" {
    var b = BareRuntime{};
    try b.init();
    defer b.deinit();

    var name_buf = [_]u8{ 'M', 'o', 'v', 'e', 0 };
    var sys = systemParams(@ptrCast(&name_buf), c.KE_PHASE_UPDATE);
    sys.execute = &noopBody;
    try testing.expect(b.rt().register_system.?(b.rt(), &sys, null) != 0);
    scribble(&name_buf);

    try testing.expectEqualStrings("Move", std.mem.span(b.registered(0).params.name));
}

test "a registered system keeps its own copy of the access list when it declares no query" {
    var b = BareRuntime{};
    try b.init();
    defer b.deinit();

    var list = [_]c.ke_component_access{ access(7, c.KE_ACCESS_WRITE), access(9, c.KE_ACCESS_READ) };
    var sys = systemParams("Plain", c.KE_PHASE_UPDATE);
    sys.execute = &noopBody;
    sys.access_list = &list;
    sys.access_count = list.len;
    try testing.expect(b.rt().register_system.?(b.rt(), &sys, null) != 0);
    scribble(std.mem.sliceAsBytes(&list));

    const kept = b.registered(0).params;
    try testing.expectEqual(@as(usize, 2), @as(usize, kept.access_count));
    try testing.expectEqual(@as(c.ke_component_id, 7), kept.access_list[0].cid);
    try testing.expectEqual(@as(c.ke_component_id, 9), kept.access_list[1].cid);
}

test "a system declaring more queries than a system can hold is refused instead of truncated" {
    var b = BareRuntime{};
    try b.init();
    defer b.deinit();

    var queries: [KE_MAX_QUERIES_PER_SYSTEM + 1]c.ke_query_decl = undefined;
    for (&queries) |*q| {
        q.* = std.mem.zeroes(c.ke_query_decl);
        q.terms[0] = access(1, c.KE_ACCESS_READ);
        q.term_count = 1;
    }
    var sys = systemParams("Greedy", c.KE_PHASE_UPDATE);
    sys.execute = &noopBody;
    sys.queries = &queries;
    sys.query_count = queries.len;

    var err: [*c]c.ke_error = null;
    try testing.expectEqual(@as(c.ke_system_id, 0), b.rt().register_system.?(b.rt(), &sys, &err));
    try testing.expect(err != null);
    try testing.expectEqualStrings("ke.error.invalid_argument", std.mem.span(err.*.type.*.name));
}

test "a query declaring more terms than a query can hold is refused instead of truncated" {
    var b = BareRuntime{};
    try b.init();
    defer b.deinit();

    var q = std.mem.zeroes(c.ke_query_decl);
    q.term_count = MAX_TERMS + 1;
    var sys = systemParams("Wide", c.KE_PHASE_UPDATE);
    sys.execute = &noopBody;
    sys.queries = &q;
    sys.query_count = 1;

    var err: [*c]c.ke_error = null;
    try testing.expectEqual(@as(c.ke_system_id, 0), b.rt().register_system.?(b.rt(), &sys, &err));
    try testing.expect(err != null);
}

var inline_failure: ?*const c.ke_error_type = null;
var inline_token: u8 = 0;

fn inlineDispatch(_: [*c]c.ke_scheduler, func: c.ke_task_func, data: ?*anyopaque) callconv(.c) ?*c.ke_task {
    inline_failure = null;
    func.?(data, &inline_failure);
    return @ptrCast(&inline_token);
}

fn inlineDispatchPinned(self: [*c]c.ke_scheduler, _: u32, func: c.ke_task_func, data: ?*anyopaque) callconv(.c) ?*c.ke_task {
    return inlineDispatch(self, func, data);
}

fn inlineWait(_: [*c]c.ke_scheduler, _: ?*c.ke_task, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    if (inline_failure) |t| {
        E.failWithType(out_error, t, "inline task failed", @src());
        return false;
    }
    return true;
}

const InlineRuntime = struct {
    bare: BareRuntime = .{},

    fn init(self: *InlineRuntime) !void {
        self.bare.scheduler.dispatch = @ptrCast(&inlineDispatch);
        self.bare.scheduler.dispatch_pinned = @ptrCast(&inlineDispatchPinned);
        self.bare.scheduler.wait = @ptrCast(&inlineWait);
        try self.bare.init();
    }

    fn rt(self: *InlineRuntime) *c.ke_runtime {
        return self.bare.rt();
    }
};

const PhaseLog = struct {
    seen: [16]c_int = undefined,
    count: usize = 0,
};

fn phaseLogBody(ctx: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    _ = ctx;
    const entry: *const PhaseLogEntry = @ptrCast(@alignCast(ud.?));
    entry.log.seen[entry.log.count] = entry.phase;
    entry.log.count += 1;
    return true;
}

const PhaseLogEntry = struct {
    log: *PhaseLog,
    phase: c_int,
};

test "the startup phase runs once, before the first tick's other phases" {
    var r = InlineRuntime{};
    try r.init();

    var log = PhaseLog{};
    const phases = [_]c_int{ c.KE_PHASE_UPDATE, c.KE_PHASE_STARTUP, c.KE_PHASE_PRE_UPDATE };
    var entries: [phases.len]PhaseLogEntry = undefined;
    for (phases, 0..) |ph, i| {
        entries[i] = .{ .log = &log, .phase = ph };
        var sys = systemParams("Logged", ph);
        sys.execute = &phaseLogBody;
        sys.user_data = &entries[i];
        try testing.expect(r.rt().register_system.?(r.rt(), &sys, null) != 0);
    }

    for (0..3) |_| try testing.expect(r.rt().tick.?(r.rt(), 0.001, null));
    r.bare.deinit();

    try testing.expectEqual(@as(c_int, c.KE_PHASE_STARTUP), log.seen[0]);
    var startups: usize = 0;
    for (log.seen[0..log.count]) |ph| {
        if (ph == c.KE_PHASE_STARTUP) startups += 1;
    }
    try testing.expectEqual(@as(usize, 1), startups);
}

test "the shutdown phase runs once when the runtime is destroyed, after every tick" {
    var r = InlineRuntime{};
    try r.init();

    var log = PhaseLog{};
    const phases = [_]c_int{ c.KE_PHASE_SHUTDOWN, c.KE_PHASE_UPDATE };
    var entries: [phases.len]PhaseLogEntry = undefined;
    for (phases, 0..) |ph, i| {
        entries[i] = .{ .log = &log, .phase = ph };
        var sys = systemParams("Logged", ph);
        sys.execute = &phaseLogBody;
        sys.user_data = &entries[i];
        try testing.expect(r.rt().register_system.?(r.rt(), &sys, null) != 0);
    }

    for (0..2) |_| try testing.expect(r.rt().tick.?(r.rt(), 0.001, null));
    try testing.expectEqual(@as(usize, 2), log.count);
    r.bare.deinit();

    try testing.expectEqual(@as(usize, 3), log.count);
    try testing.expectEqual(@as(c_int, c.KE_PHASE_SHUTDOWN), log.seen[2]);
}

fn fakeQueryRegister(_: ?*c.ke_ecs, _: [*c]const c.ke_component_id, _: usize) callconv(.c) c.ke_query_id {
    return 1;
}

fn fakeQueryResolveOverflowing(_: ?*c.ke_ecs, _: c.ke_query_id, out: [*c]c.ke_ecs_segment, max: usize, out_count: [*c]usize) callconv(.c) void {
    for (0..max) |i| out[i] = std.mem.zeroes(c.ke_ecs_segment);
    out_count.* = max + 8;
}

fn fakeComponentSize(_: ?*c.ke_ecs, _: c.ke_component_id) callconv(.c) usize {
    return 4;
}

fn overflowingQueryRuntime(r: *InlineRuntime, phase: c_int) !void {
    r.bare.ecs.query_register = @ptrCast(&fakeQueryRegister);
    r.bare.ecs.query_resolve = @ptrCast(&fakeQueryResolveOverflowing);
    r.bare.ecs.component_size = @ptrCast(&fakeComponentSize);
    try r.init();

    var q = std.mem.zeroes(c.ke_query_decl);
    q.terms[0] = access(1, c.KE_ACCESS_READ);
    q.term_count = 1;
    var sys = systemParams("Fragmented", phase);
    sys.execute = &noopBody;
    sys.queries = &q;
    sys.query_count = 1;
    try testing.expect(r.rt().register_system.?(r.rt(), &sys, null) != 0);
}

test "a sim query matching more segments than the runtime holds fails the tick instead of dropping them" {
    var r = InlineRuntime{};
    try overflowingQueryRuntime(&r, c.KE_PHASE_UPDATE);
    defer r.bare.deinit();

    var err: [*c]c.ke_error = null;
    try testing.expect(!r.rt().tick.?(r.rt(), 0.001, &err));
    try testing.expect(err != null);
}

test "a render query matching more segments than the runtime holds fails the tick instead of dropping them" {
    var r = InlineRuntime{};
    try overflowingQueryRuntime(&r, c.KE_PHASE_RENDER);
    defer r.bare.deinit();

    var err: [*c]c.ke_error = null;
    try testing.expect(!r.rt().tick.?(r.rt(), 0.001, &err));
    try testing.expect(err != null);
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

fn parallelWorker(_: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
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
    return true;
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

fn orderWorker(_: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const slot: *OrderSlot = @ptrCast(@alignCast(ud.?));
    const i = slot.probe.next.fetchAdd(1, .acq_rel);
    if (i < slot.probe.slots.len) slot.probe.slots[i].store(slot.tag, .release);
    return true;
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

fn gatedRenderBody(_: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    while (!g_gated_render_may_finish.load(.acquire)) std.atomic.spinLoopHint();
    _ = g_gated_render_runs.fetchAdd(1, .acq_rel);
    return true;
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

fn extractSimWriter(ctx: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    var seg_count: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &seg_count);
    if (segs == null) return true;
    for (0..seg_count) |s| {
        const col: [*]i32 = @ptrCast(@alignCast(segs[s].columns[0] orelse continue));
        for (0..segs[s].count) |i| col[i] = 42;
    }
    return true;
}

fn extractRenderReader(ctx: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    var seg_count: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &seg_count);
    if (segs != null and seg_count > 0 and segs[0].count > 0) {
        if (segs[0].columns[0]) |col| {
            const typed: [*]const i32 = @ptrCast(@alignCast(col));
            g_extract_probe.seen.store(typed[0], .release);
            g_extract_probe.seen_ptr.store(@intFromPtr(col), .release);
        }
    }
    _ = g_extract_probe.runs.fetchAdd(1, .acq_rel);
    return true;
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

fn extractPosVelReader(ctx: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    var seg_count: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &seg_count);
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
    return true;
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
    debugComputeWaves(null, 0, &assignments, &wave_count);
    try testing.expectEqual(@as(u32, 0), wave_count);
}

test "a single system occupies one wave" {
    const acc = [_]c.ke_component_access{access(1, c.KE_ACCESS_WRITE)};
    const sys = [_]c.ke_runtime_system_params{waveSystem(&acc, 1)};

    var assignments = [_]u32{99};
    var wave_count: u32 = 0;
    debugComputeWaves(&sys, 1, &assignments, &wave_count);

    try testing.expectEqual(@as(u32, 1), wave_count);
    try testing.expectEqual(@as(u32, 0), assignments[0]);
}

test "systems writing different components share a wave" {
    const a = [_]c.ke_component_access{access(1, c.KE_ACCESS_WRITE)};
    const b = [_]c.ke_component_access{access(2, c.KE_ACCESS_WRITE)};
    const sys = [_]c.ke_runtime_system_params{ waveSystem(&a, 1), waveSystem(&b, 1) };

    var assignments = [_]u32{ 99, 99 };
    var wave_count: u32 = 0;
    debugComputeWaves(&sys, 2, &assignments, &wave_count);

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
    debugComputeWaves(&sys, 2, &assignments, &wave_count);

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
    debugComputeWaves(&sys, 2, &assignments, &wave_count);

    try testing.expectEqual(@as(u32, 2), wave_count);
}

test "two readers of the same component share a wave" {
    const a = [_]c.ke_component_access{access(7, c.KE_ACCESS_READ)};
    const b = [_]c.ke_component_access{access(7, c.KE_ACCESS_READ)};
    const sys = [_]c.ke_runtime_system_params{ waveSystem(&a, 1), waveSystem(&b, 1) };

    var assignments = [_]u32{ 99, 99 };
    var wave_count: u32 = 0;
    debugComputeWaves(&sys, 2, &assignments, &wave_count);

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
    debugComputeWaves(&sys, 4, &assignments, &wave_count);

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
    debugComputeWaves(&sys, 3, &assignments, &wave_count);

    try testing.expectEqual(@as(u32, 1), wave_count);
    try testing.expectEqual(assignments[0], assignments[1]);
    try testing.expectEqual(assignments[1], assignments[2]);
}

const SpawnProbe = struct {
    ids: [3]c.ke_entity = .{ c.KE_ENTITY_INVALID, c.KE_ENTITY_INVALID, c.KE_ENTITY_INVALID },
    calls: Counter = Counter.init(0),
    cid: c.ke_component_id = 0,
};

fn spawnerBody(ctx: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const probe: *SpawnProbe = @ptrCast(@alignCast(ud.?));
    const cmds = ctx.?.commands;
    for (&probe.ids) |*slot| slot.* = cmds.*.spawn.?(cmds, null);
    _ = probe.calls.fetchAdd(1, .acq_rel);
    return true;
}

test "a deferred spawn is applied at the wave barrier" {
    var f = try Fixture.init();
    defer f.deinit();

    resetDeferApplied();

    var probe = SpawnProbe{};
    var sys = systemParams("Spawner", c.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &spawnerBody;
    try testing.expect(f.rt().register_system.?(f.rt(), &sys, null) != 0);

    try testing.expect(f.tick(1.0 / 60.0));
    try testing.expectEqual(@as(u32, 1), probe.calls.load(.acquire));
    try testing.expectEqual(@as(u32, 3), deferAppliedCount());
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
    cid: c.ke_component_id = 0,
    ok: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

fn mutatorBody(ctx: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const probe: *MutatorProbe = @ptrCast(@alignCast(ud.?));
    const cmds = ctx.?.commands;
    const attached = cmds.*.attach.?(cmds, 42, probe.cid, &probe.payload, 1, null);
    const detached = cmds.*.detach.?(cmds, 42, probe.cid, null);
    const despawned = cmds.*.despawn.?(cmds, 42, null);
    probe.ok.store(attached and detached and despawned, .release);
    return true;
}

test "deferred attach detach and despawn are applied at the barrier" {
    var f = try Fixture.init();
    defer f.deinit();

    resetDeferApplied();

    var probe = MutatorProbe{};
    probe.cid = f.ecs().component_register.?(f.ecs(), "mutator_probe", 1, null, 0, null);
    var sys = systemParams("Mutator", c.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &mutatorBody;
    try testing.expect(f.rt().register_system.?(f.rt(), &sys, null) != 0);

    try testing.expect(f.tick(1.0 / 60.0));
    try testing.expect(probe.ok.load(.acquire));
    try testing.expectEqual(@as(u32, 3), deferAppliedCount());
}

fn repeatSpawnerBody(ctx: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const cmds = ctx.?.commands;
    _ = cmds.*.spawn.?(cmds, null);
    return true;
}

const RefusalProbe = struct {
    cid: c.ke_component_id = 0,
    wrong_size_refused: bool = false,
    wrong_size_error: ?*const c.ke_error_type = null,
    render_refused: bool = false,
    render_error: ?*const c.ke_error_type = null,
};

fn wrongSizeBody(ctx: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const probe: *RefusalProbe = @ptrCast(@alignCast(ud.?));
    const cmds = ctx.?.commands;
    var payload: [8]u8 = undefined;
    var err: [*c]c.ke_error = null;
    probe.wrong_size_refused = !cmds.*.attach.?(cmds, 42, probe.cid, &payload, payload.len, &err);
    if (err != null) probe.wrong_size_error = err.*.type;
    return true;
}

fn renderBody(ctx: ?*c.ke_system_ctx, ud: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const probe: *RefusalProbe = @ptrCast(@alignCast(ud.?));
    const cmds = ctx.?.commands;
    var err: [*c]c.ke_error = null;
    probe.render_refused = cmds.*.spawn.?(cmds, &err) == c.KE_ENTITY_INVALID;
    if (err != null) probe.render_error = err.*.type;
    return true;
}

test "an attach whose payload size differs from the component size is refused with an error" {
    var f = try Fixture.init();
    defer f.deinit();

    resetDeferApplied();

    var probe = RefusalProbe{};
    probe.cid = f.ecs().component_register.?(f.ecs(), "refusal_probe", 1, null, 0, null);
    var sys = systemParams("WrongSize", c.KE_PHASE_UPDATE);
    sys.user_data = &probe;
    sys.execute = &wrongSizeBody;
    try testing.expect(f.rt().register_system.?(f.rt(), &sys, null) != 0);

    try testing.expect(f.tick(1.0 / 60.0));
    try testing.expect(probe.wrong_size_refused);
    try testing.expect(probe.wrong_size_error == E.typeOf(.invalid_argument));
    try testing.expectEqual(@as(u32, 0), deferAppliedCount());
}

test "the render phase refuses to record a structural change" {
    var f = try Fixture.init();
    defer f.deinit();

    var probe = RefusalProbe{};
    var sys = systemParams("RenderSpawner", c.KE_PHASE_RENDER);
    sys.user_data = &probe;
    sys.execute = &renderBody;
    try testing.expect(f.rt().register_system.?(f.rt(), &sys, null) != 0);

    try testing.expect(f.tick(1.0 / 60.0));
    f.flushRender();
    try testing.expect(probe.render_refused);
    try testing.expect(probe.render_error == E.typeOf(.not_supported));
}

test "the defer queue drains between ticks" {
    var f = try Fixture.init();
    defer f.deinit();

    resetDeferApplied();

    var sys = systemParams("RepeatSpawner", c.KE_PHASE_UPDATE);
    sys.execute = &repeatSpawnerBody;
    try testing.expect(f.rt().register_system.?(f.rt(), &sys, null) != 0);

    for (0..5) |_| try testing.expect(f.tick(1.0 / 60.0));

    try testing.expectEqual(@as(u32, 5), deferAppliedCount());
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

fn parallelReaderBody(ctx: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    var seg_count: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &seg_count);
    if (segs == null) return true;

    var sink: f32 = 0.0;
    for (0..seg_count) |s| {
        const col: [*]const Vec3 = @ptrCast(@alignCast(segs[s].columns[0] orelse continue));
        for (0..segs[s].count) |i| sink += col[i].x;
    }
    std.mem.doNotOptimizeAway(sink);
    return true;
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
    debugComputeWaves(&sysz, 2, &waves, &wave_count);
    try testing.expectEqual(waves[0], waves[1]);

    for (0..300) |_| try testing.expect(f.tick(1.0 / 60.0));
}

var g_pv_sum: f64 = 0.0;

fn posVelBody(ctx: ?*c.ke_system_ctx, _: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    var seg_count: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &seg_count);
    if (segs == null) return true;
    for (0..seg_count) |s| {
        const pc: [*]const Vec3 = @ptrCast(@alignCast(segs[s].columns[0] orelse continue));
        const vc: [*]const Vec3 = @ptrCast(@alignCast(segs[s].columns[1] orelse continue));
        for (0..segs[s].count) |i| g_pv_sum += @as(f64, pc[i].x) + @as(f64, vc[i].x);
    }
    return true;
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

test "creating, ticking and destroying a runtime leaves no block allocated" {
    var f = try Fixture.init();
    var sys = systemParams("LeakProbe", c.KE_PHASE_UPDATE);
    sys.execute = &repeatSpawnerBody;
    try testing.expect(f.rt().register_system.?(f.rt(), &sys, null) != 0);
    try testing.expect(f.tick(1.0 / 60.0));
    f.deinit();
    try heap.expectNoLeaks();
}

test "a runtime with no system registered leaves no block allocated" {
    var f = try Fixture.init();
    f.deinit();
    try heap.expectNoLeaks();
}
