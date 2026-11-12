//! What a system body is given: the segments its queries resolved to, its share of them, and the
//! queue of structural changes it records, applied once its wave has returned.

const std = @import("std");

const abi_ecs = @import("abi_ecs");
const abi_result = @import("abi_result");
const abi_scheduler = @import("abi_scheduler");
const heap = @import("heap");

const R = @import("result").Result(.{});
const log = std.log.scoped(.scheduler);

const c = abi_scheduler.c;
const gpa = heap.gpa;

const arena_alignment: std.mem.Alignment = .@"16";

const Kind = enum { spawn, attach, detach, despawn, callback };

const Command = struct {
    kind: Kind,
    entity: c.ke_entity = 0,
    id: c.ke_component_id = 0,
    offset: usize = 0,
    size: usize = 0,
    func: abi_ecs.c.ke_defer_fn = null,
};

/// The structural changes recorded by one body, or by the caller of `run` between runs. A body
/// never changes the world directly: a spawn reserves its entity at once so later commands can name
/// it, and `flush` applies every command in recorded order once the whole wave has returned, so no
/// body sees storage move under it and the next wave sees every change of this one. Payloads are
/// copied into `arena`, whose offsets mean something only until the next flush.
pub const Queue = struct {
    commands: std.ArrayList(Command) = .empty,
    arena: std.array_list.Aligned(u8, arena_alignment) = .empty,

    pub fn deinit(q: *Queue) void {
        q.commands.deinit(gpa);
        q.arena.deinit(gpa);
    }

    fn push(q: *Queue, data: ?*const anyopaque, size: usize) R.Error!usize {
        if (size == 0) return 0;
        const offset = arena_alignment.forward(q.arena.items.len);
        try q.arena.resize(gpa, offset + size);
        if (data) |d| @memcpy(q.arena.items[offset..][0..size], @as([*]const u8, @ptrCast(d))[0..size]);
        return offset;
    }

    /// Applies the recorded commands in order, then empties the queue. The first command the ecs
    /// refuses stops the flush; the commands after it are dropped and its failure is returned.
    pub fn flush(q: *Queue, ecs: *abi_ecs.c.ke_ecs) R.Error!void {
        defer {
            q.commands.clearRetainingCapacity();
            q.arena.clearRetainingCapacity();
        }
        for (q.commands.items) |cmd| {
            switch (cmd.kind) {
                .spawn => if (ecs.entity_materialize) |materialize| try R.check(materialize(ecs, cmd.entity)),
                .attach => {
                    var slot: ?*anyopaque = null;
                    try R.check(ecs.component_add.?(ecs, cmd.entity, cmd.id, &slot));
                    if (slot != null and cmd.size > 0)
                        @memcpy(@as([*]u8, @ptrCast(slot.?))[0..cmd.size], q.arena.items[cmd.offset..][0..cmd.size]);
                },
                .detach => try R.check(ecs.component_remove.?(ecs, cmd.entity, cmd.id)),
                .despawn => try R.check(ecs.entity_destroy.?(ecs, cmd.entity)),
                .callback => try R.check(cmd.func.?(ecs, if (cmd.size > 0) q.arena.items[cmd.offset..].ptr else null)),
            }
        }
    }
};

/// The segments one query resolves into, with one column pointer per term for each segment; they
/// grow until the world's answer fits.
pub const Segments = struct {
    segments: []abi_ecs.c.ke_ecs_segment = &.{},
    columns: []?*anyopaque = &.{},
    count: usize = 0,

    pub fn deinit(s: *Segments) void {
        gpa.free(s.segments);
        gpa.free(s.columns);
        s.* = .{};
    }

    fn reserve(s: *Segments, needed: usize, terms: usize) R.Error!void {
        if (needed <= s.segments.len) return;
        const segments = try gpa.alloc(abi_ecs.c.ke_ecs_segment, needed);
        const columns = gpa.alloc(?*anyopaque, needed * terms) catch |err| {
            gpa.free(segments);
            return err;
        };
        s.deinit();
        s.segments = segments;
        s.columns = columns;
    }

    /// Resolves `query` into the buffers, starting from the one segment the ecs requires at least,
    /// growing them to the count the ecs reports and asking once more; nothing changes the world
    /// between the two calls.
    pub fn resolve(s: *Segments, ecs: *abi_ecs.c.ke_ecs, query: abi_ecs.c.ke_query_id, terms: usize) R.Error!void {
        try s.reserve(1, terms);
        var matched: usize = 0;
        try R.check(ecs.query_resolve.?(ecs, query, s.segments.ptr, s.segments.len, @ptrCast(s.columns.ptr), &matched));
        if (matched > s.segments.len) {
            try s.reserve(matched, terms);
            try R.check(ecs.query_resolve.?(ecs, query, s.segments.ptr, s.segments.len, @ptrCast(s.columns.ptr), &matched));
            if (matched > s.segments.len) return error.General;
        }
        s.count = matched;
    }
};

/// What one query of a system shows its body: the segments it resolved to before the wave, or the
/// one segment of the snapshot a pipelined phase took.
pub const View = struct {
    segments: [*]const abi_ecs.c.ke_ecs_segment = undefined,
    count: usize = 0,

    pub fn of(s: *const Segments) View {
        return .{ .segments = s.segments.ptr, .count = s.count };
    }
};

/// The copy of what one query matched, taken for a pipelined phase before it is dispatched: the
/// entities and, for every term with storage, its column, gathered into one segment. The buffers
/// are kept and reused across ticks.
pub const Snapshot = struct {
    entities: std.ArrayList(abi_ecs.c.ke_entity) = .empty,
    columns: []std.array_list.Aligned(u8, arena_alignment) = &.{},
    pointers: []?*anyopaque = &.{},
    sizes: []usize = &.{},
    segment: abi_ecs.c.ke_ecs_segment = undefined,

    pub fn deinit(snap: *Snapshot) void {
        snap.entities.deinit(gpa);
        for (snap.columns) |*col| col.deinit(gpa);
        gpa.free(snap.columns);
        gpa.free(snap.pointers);
        gpa.free(snap.sizes);
        snap.* = .{};
    }

    /// Copies the segments of `raw` into the snapshot and returns the view of its one segment.
    pub fn take(snap: *Snapshot, ecs: *abi_ecs.c.ke_ecs, raw: *const Segments, terms: []const c.ke_id_access) R.Error!View {
        if (snap.sizes.len != terms.len) {
            snap.deinit();
            snap.sizes = try gpa.alloc(usize, terms.len);
            snap.pointers = try gpa.alloc(?*anyopaque, terms.len);
            snap.columns = try gpa.alloc(std.array_list.Aligned(u8, arena_alignment), terms.len);
            for (terms, snap.sizes, snap.columns) |t, *size, *col| {
                size.* = ecs.component_size.?(ecs, t.id);
                col.* = .empty;
            }
        }
        snap.entities.clearRetainingCapacity();
        for (snap.columns) |*col| col.clearRetainingCapacity();
        for (raw.segments[0..raw.count]) |seg| {
            if (seg.count == 0) continue;
            try snap.entities.appendSlice(gpa, seg.entities.?[0..seg.count]);
            for (snap.sizes, snap.columns, 0..) |size, *col, t| {
                if (size == 0) continue;
                const bytes: [*]const u8 = @ptrCast(seg.columns.?[t].?);
                try col.appendSlice(gpa, bytes[0 .. seg.count * size]);
            }
        }
        for (snap.sizes, snap.columns, snap.pointers) |size, *col, *ptr| ptr.* = if (size == 0) null else col.items.ptr;
        snap.segment = .{ .entities = snap.entities.items.ptr, .count = snap.entities.items.len, .columns = snap.pointers.ptr, .column_count = @intCast(terms.len) };
        return .{ .segments = @ptrCast(&snap.segment), .count = @intFromBool(snap.entities.items.len > 0) };
    }
};

/// The state behind both the `ke_scheduler_ctx` and the `ke_ecs_commands` of one body call, or of
/// the caller of `tick`. `queue` is null where recording is refused; `views` show what the system's
/// queries match.
pub const Context = struct {
    ecs: *abi_ecs.c.ke_ecs,
    queue: ?*Queue,
    views: []const View = &.{},
    slice_index: u32 = 0,
    slice_count: u32 = 1,
    ctx: c.ke_scheduler_ctx = undefined,
    commands: abi_ecs.c.ke_ecs_commands = undefined,

    /// Points the context and the commands at this state. The state must not move while either is
    /// in use.
    pub fn bind(self: *Context) void {
        self.commands = .{
            .handle = self,
            .spawn = &spawn,
            .attach = &attach,
            .detach = &detach,
            .despawn = &despawn,
            .@"defer" = &deferCall,
        };
        self.ctx = .{ .handle = self, .commands = &self.commands, .view = &view, .slice = &slice };
    }
};

fn contextOf(ctx: ?*c.ke_scheduler_ctx) ?*Context {
    return @ptrCast(@alignCast((ctx orelse return null).handle));
}

fn queueOf(commands: ?*abi_ecs.c.ke_ecs_commands) R.Error!*Context {
    const cmds = commands orelse return error.InvalidArgument;
    const state: *Context = @ptrCast(@alignCast(cmds.handle orelse return error.InvalidArgument));
    if (state.queue == null) return error.NotSupported;
    return state;
}

fn refused(comptime what: []const u8, err: R.Error) abi_result.c.ke_result {
    log.warn("recording " ++ what ++ " failed: {t}", .{err});
    return R.code(err);
}

/// Slot `view`: the segments of the query at `query_index`, or null and a count of zero past the
/// system's queries.
fn view(ctx: ?*c.ke_scheduler_ctx, query_index: u32, out_count: ?*usize) callconv(.c) ?[*]const abi_ecs.c.ke_ecs_segment {
    if (out_count) |out| out.* = 0;
    const state = contextOf(ctx) orelse return null;
    if (query_index >= state.views.len) return null;
    const v = state.views[query_index];
    if (out_count) |out| out.* = v.count;
    return v.segments;
}

/// Slot `slice`: the share of its entity set this call owns.
fn slice(ctx: ?*c.ke_scheduler_ctx, out_index: ?*u32, out_count: ?*u32) callconv(.c) void {
    const state = contextOf(ctx);
    if (out_index) |out| out.* = if (state) |s| s.slice_index else 0;
    if (out_count) |out| out.* = if (state) |s| s.slice_count else 1;
}

/// Slot `spawn`: reserves the entity at once, so the queue can name it; it enters the world when
/// the queue is flushed.
fn spawn(commands: ?*abi_ecs.c.ke_ecs_commands, out_entity: ?*c.ke_entity) callconv(.c) abi_result.c.ke_result {
    const out = out_entity orelse return refused("a spawn", error.InvalidArgument);
    out.* = abi_ecs.c.KE_ENTITY_INVALID;
    const state = queueOf(commands) catch |err| return refused("a spawn", err);
    var entity: c.ke_entity = abi_ecs.c.KE_ENTITY_INVALID;
    R.check(state.ecs.entity_reserve.?(state.ecs, &entity)) catch |err| return refused("a spawn", err);
    state.queue.?.commands.append(gpa, .{ .kind = .spawn, .entity = entity }) catch |err| return refused("a spawn", err);
    out.* = entity;
    return R.ok;
}

/// Slot `attach`: copies the payload now, checked against the component's size.
fn attach(commands: ?*abi_ecs.c.ke_ecs_commands, entity: c.ke_entity, id: c.ke_component_id, data: ?*const anyopaque, size: usize) callconv(.c) abi_result.c.ke_result {
    recordAttach(commands, entity, id, data, size) catch |err| return refused("an attach", err);
    return R.ok;
}

fn recordAttach(commands: ?*abi_ecs.c.ke_ecs_commands, entity: c.ke_entity, id: c.ke_component_id, data: ?*const anyopaque, size: usize) R.Error!void {
    const state = try queueOf(commands);
    if (size != 0 and size != state.ecs.component_size.?(state.ecs, id)) return error.InvalidArgument;
    const q = state.queue.?;
    const offset = try q.push(data, size);
    try q.commands.append(gpa, .{ .kind = .attach, .entity = entity, .id = id, .offset = offset, .size = size });
}

/// Slot `detach`.
fn detach(commands: ?*abi_ecs.c.ke_ecs_commands, entity: c.ke_entity, id: c.ke_component_id) callconv(.c) abi_result.c.ke_result {
    const state = queueOf(commands) catch |err| return refused("a detach", err);
    state.queue.?.commands.append(gpa, .{ .kind = .detach, .entity = entity, .id = id }) catch |err| return refused("a detach", err);
    return R.ok;
}

/// Slot `despawn`.
fn despawn(commands: ?*abi_ecs.c.ke_ecs_commands, entity: c.ke_entity) callconv(.c) abi_result.c.ke_result {
    const state = queueOf(commands) catch |err| return refused("a despawn", err);
    state.queue.?.commands.append(gpa, .{ .kind = .despawn, .entity = entity }) catch |err| return refused("a despawn", err);
    return R.ok;
}

/// Slot `defer`: copies the user bytes now; the flush calls `func` with the world and the copy.
fn deferCall(commands: ?*abi_ecs.c.ke_ecs_commands, func: abi_ecs.c.ke_defer_fn, user: ?*const anyopaque, size: usize) callconv(.c) abi_result.c.ke_result {
    recordCall(commands, func, user, size) catch |err| return refused("a deferred call", err);
    return R.ok;
}

fn recordCall(commands: ?*abi_ecs.c.ke_ecs_commands, func: abi_ecs.c.ke_defer_fn, user: ?*const anyopaque, size: usize) R.Error!void {
    const state = try queueOf(commands);
    if (func == null) return error.InvalidArgument;
    const q = state.queue.?;
    const offset = try q.push(user, size);
    try q.commands.append(gpa, .{ .kind = .callback, .func = func, .offset = offset, .size = size });
}
