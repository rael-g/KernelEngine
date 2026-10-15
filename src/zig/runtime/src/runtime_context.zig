//! The context a system body receives and the queue of structural changes it records, applied
//! after its wave returns.

const std = @import("std");

const c = @import("runtime_c.zig").c;
const heap = @import("heap");
const alloc = @import("runtime_alloc.zig");
const cAlloc = alloc.cAlloc;
const cFree = alloc.cFree;
const cAllocBytes = alloc.cAllocBytes;
const cFreeBytes = alloc.cFreeBytes;

const E = @import("kerror").Errors(c);

pub const DeferKind = enum(c_int) {
    spawn = 1,
    attach = 2,
    detach = 3,
    despawn = 4,
    callback = 5,
};

/// One recorded structural change. `kind` decides which other fields mean something: `cid` names
/// the component for attach and detach, `attach_offset` and `attach_size` locate the payload in the
/// queue's arena for attach and callback, and `fn_` is set only for callback.
pub const DeferCommand = struct {
    kind: DeferKind,
    entity: c.ke_entity,
    cid: c.ke_component_id,
    attach_offset: usize,
    attach_size: usize,
    fn_: c.ke_defer_fn,
};

/// The structural changes one package records during its body. A body never changes the world
/// directly: its commands append here, a spawn reserving its entity id at once so later commands
/// can name it, and `deferFlush` applies them in recorded order after the whole wave has
/// returned. So no body of a wave sees storage move under it, and the next wave sees every change
/// of the previous one. The queue starts empty for each package and grows as commands are
/// recorded; `runtimeRunPhase` frees its buffers after the flush, so arena offsets are meaningful
/// only within the wave that recorded them.
pub const DeferQueue = struct {
    cmds: ?[*]DeferCommand = null,
    count: usize = 0,
    capacity: usize = 0,
    arena: ?[*]u8 = null,
    arena_used: usize = 0,
    arena_capacity: usize = 0,
};

/// The state behind both the `ke_system_ctx` and the `ke_ecs_commands` of one package, which share
/// it. `runtimeRunPhase` sets it for each package: `defer_q` is null in the render phase, where no
/// body may record a change, and the segment arrays point at what the wave resolved for the system.
pub const CtxState = struct {
    ecs: ?*c.ke_ecs,
    access_list: ?[*]const c.ke_component_access,
    access_count: u32,
    system_name: [*c]const u8,
    defer_q: ?*DeferQueue,
    seg_ptrs: ?[*]const ?[*]const c.ke_ecs_segment,
    seg_counts: ?[*]const usize,
    view_query_count: u32,
    slice_index: u32,
    slice_count: u32,
};

pub fn ctxOf(ptr: ?*c.ke_system_ctx) ?*CtxState {
    const ctx = ptr orelse return null;
    return @ptrCast(@alignCast(ctx.handle));
}

pub fn commandsOf(ptr: ?*c.ke_ecs_commands) ?*CtxState {
    const cmds = ptr orelse return null;
    return @ptrCast(@alignCast(cmds.handle));
}

/// Binds the context and the commands of one package to its `CtxState`. The package must not move
/// until its wave has been waited for.
pub fn bindCtx(ctx: *c.ke_system_ctx, commands: *c.ke_ecs_commands, state: *CtxState) void {
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

/// Slot `view` of every system context. Returns the segments resolved for the query before the
/// wave was dispatched, or the copies made by `runtimeExtractRenderState` for a render system, and
/// their number through the count pointer. A null context, an index past the system's queries or a
/// system with no queries returns null and a count of zero; no error is reported.
pub fn ctxView(ctx: ?*c.ke_system_ctx, query_index: u32, out_count: [*c]usize) callconv(.c) [*c]const c.ke_ecs_segment {
    if (out_count != null) out_count.* = 0;
    const s = ctxOf(ctx) orelse return null;
    if (s.seg_ptrs == null or query_index >= s.view_query_count) return null;
    if (out_count != null) out_count.* = s.seg_counts.?[query_index];
    return s.seg_ptrs.?[query_index];
}

/// Grows the command array of a queue by doubling until it holds the needed count, keeping the
/// recorded commands. Returns false when the allocation fails, leaving the queue as it was.
pub fn deferReserve(q: *DeferQueue, needed: usize) bool {
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

pub const defer_arena_align: usize = 16;

/// Appends the bytes at the data pointer to the arena of a queue and returns their offset, which
/// the recorded command keeps, since the arena moves when it grows. A null data pointer only
/// reserves the space. A size of zero records nothing and returns zero. The maximum usize value is
/// returned when the arena cannot grow.
pub fn deferArenaPush(q: *DeferQueue, data: ?*const anyopaque, size: usize) usize {
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

/// Slot `slice` of every system context. Reports which share of its entity set the body has, as an
/// index and a count; a null context reports index 0 of 1.
pub fn ctxSlice(ctx: ?*c.ke_system_ctx, out_index: [*c]u32, out_count: [*c]u32) callconv(.c) void {
    const s = ctxOf(ctx);
    if (out_index != null) out_index.* = if (s) |st| st.slice_index else 0;
    if (out_count != null) out_count.* = if (s) |st| st.slice_count else 1;
}

/// Finds the queue a recording call writes to. It fails with `invalid_argument` for a null or
/// unbound commands table, and with `not_supported` when the package has no queue, which is the
/// case in the render phase.
pub fn recordTarget(self: ?*c.ke_ecs_commands, out_error: [*c][*c]c.ke_error, src: std.builtin.SourceLocation) ?*DeferQueue {
    const s = commandsOf(self) orelse {
        E.fail(out_error, .invalid_argument, "invalid command queue", src);
        return null;
    };
    return s.defer_q orelse {
        E.fail(out_error, .not_supported, "this phase may not change structure", src);
        return null;
    };
}

/// Appends an empty command to the queue and returns it for the caller to fill. It fails with
/// `out_of_memory` when the command array cannot grow.
pub fn recordCommand(q: *DeferQueue, out_error: [*c][*c]c.ke_error, src: std.builtin.SourceLocation) ?*DeferCommand {
    if (!deferReserve(q, q.count + 1)) {
        E.fail(out_error, .out_of_memory, "command queue is full", src);
        return null;
    }
    const cmd = &q.cmds.?[q.count];
    q.count += 1;
    return cmd;
}

/// Slot `spawn` of the commands of a body. The id is reserved at once, so the body can attach to
/// it in the same queue; the entity enters the world when `deferFlush` reaches the spawn. Fails
/// with `invalid_argument` for an unbound table, `not_supported` in the render phase,
/// `not_initialized` without a world, and `out_of_memory` when the id pool is spent or the queue
/// cannot grow; each returns the invalid entity.
pub fn commandsSpawn(self: ?*c.ke_ecs_commands, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_entity {
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

/// Slot `attach` of the commands of a body. The payload is copied into the arena now, so the
/// caller's buffer may be reused after the call. A non-zero size is checked against the component
/// size here, and the copy into the component happens in `deferFlush`. Fails, returning false,
/// with `invalid_argument` for an unbound table or a size that differs from the component's,
/// `not_supported` in the render phase, `not_initialized` without a world, and `out_of_memory`
/// when the queue or its arena cannot grow.
pub fn commandsAttach(self: ?*c.ke_ecs_commands, entity: c.ke_entity, cid: c.ke_component_id, data: ?*const anyopaque, size: usize, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
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

/// Slot `detach` of the commands of a body. Records the removal for `deferFlush`. Fails,
/// returning false, with `invalid_argument` for an unbound table, `not_supported` in the render
/// phase, and `out_of_memory` when the queue cannot grow.
pub fn commandsDetach(self: ?*c.ke_ecs_commands, entity: c.ke_entity, cid: c.ke_component_id, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const q = recordTarget(self, out_error, @src()) orelse return false;
    const cmd = recordCommand(q, out_error, @src()) orelse return false;
    cmd.kind = .detach;
    cmd.entity = entity;
    cmd.cid = cid;
    return true;
}

/// Slot `despawn` of the commands of a body. Records the destruction for `deferFlush`. Fails in
/// the same ways as `commandsDetach`.
pub fn commandsDespawn(self: ?*c.ke_ecs_commands, entity: c.ke_entity, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const q = recordTarget(self, out_error, @src()) orelse return false;
    const cmd = recordCommand(q, out_error, @src()) orelse return false;
    cmd.kind = .despawn;
    cmd.entity = entity;
    return true;
}

/// Slot `defer` of the commands of a body. `deferFlush` later calls the function with the world
/// and a pointer to a copy of the user bytes taken here, so the caller's bytes need not outlive
/// the call. Fails, returning false, with `invalid_argument` for an unbound table or a null
/// function, `not_supported` in the render phase, and `out_of_memory` when the queue or its arena
/// cannot grow.
pub fn commandsDefer(self: ?*c.ke_ecs_commands, func: c.ke_defer_fn, user: ?*const anyopaque, user_size: usize, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
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

/// Process-wide count of the commands `deferFlush` has applied, across every runtime.
pub var s_defer_applied_total: u32 = 0;

/// Applies the recorded commands in recorded order, then empties the queue. It must run only once
/// every task of the wave has returned; the caller frees the queue's buffers afterwards.
pub fn deferFlush(q: *DeferQueue, ecs: *c.ke_ecs) void {
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

pub fn deferAppliedCount() u32 {
    return s_defer_applied_total;
}
pub fn resetDeferApplied() void {
    s_defer_applied_total = 0;
}
