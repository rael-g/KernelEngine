//! The `ke_extraction` contract over two `ke_ecs` worlds, on the calling thread: pairs the synced entities of
//! the main world with entities of the render world, copies and blends the registered components into them,
//! and runs the render schedule as the render stage.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_extraction_default").logFn };

const abi_completion = @import("abi_completion");
const abi_ecs = @import("abi_ecs");
const abi_ecs_variant = @import("abi_ecs_variant");
const abi_extraction = @import("abi_extraction");
const abi_module = @import("abi_module");
const abi_result = @import("abi_result");
const abi_schedule = @import("abi_schedule");
const abi_scheduler = @import("abi_scheduler");
const abi_part = @import("abi_part");
const part = @import("part");
const heap = @import("heap");

const R = @import("result").Result(.{});
const log = std.log.scoped(.extraction);

const x = abi_extraction.c;
const e = abi_ecs.c;
const Ecs = e.ke_ecs;
const Entity = e.ke_entity;
const Cid = e.ke_component_id;
const Result = abi_result.c.ke_result;
const gpa = heap.gpa;

const no_entity: Entity = e.KE_ENTITY_INVALID;

/// A registered copy, and the byte offsets of the ENTITY fields of its render component.
const Copy = struct { main: Cid, render: Cid, size: usize, entity_offsets: []u32 };

/// A registered interpolation, and the system of the history module that copies its current value into its
/// previous one before each fixed step, registered while the module is attached.
const Interp = struct {
    main: Cid,
    previous: Cid,
    render: Cid,
    size: usize,
    entity_offsets: []u32,
    blend: x.ke_extraction_interpolate_fn,
    user: ?*anyopaque,
    terms: [2]e.ke_ecs_query_term = undefined,
    queries: [1]e.ke_ecs_query_desc = undefined,
    system: abi_schedule.c.ke_schedule_system_id = 0,
    registered: bool = false,
};

const Custom = struct { extract: x.ke_extraction_custom_fn, user: ?*anyopaque };

/// The state behind the handle, whose `api.handle` points back at it. `to_render` and `to_main` are the pairs
/// both ways; `synced`, `interpolated` and `teleported` are the tags of the main world and `frame_local` that of
/// the render world, each read through a query of its one tag. `history` is the schedule the history module
/// attached to, null while it is detached.
const State = struct {
    api: x.ke_extraction,
    executable: abi_scheduler.c.ke_scheduler_executable = .{ .run = &runAsExecutable },
    module: abi_module.c.ke_module = undefined,
    main: *Ecs,
    render: *Ecs,
    scheduler: *abi_scheduler.c.ke_scheduler,
    render_schedule: *abi_schedule.c.ke_schedule,
    synced: Cid = 0,
    interpolated: Cid = 0,
    teleported: Cid = 0,
    frame_local: Cid = 0,
    synced_query: e.ke_query_id = 0,
    interpolated_query: e.ke_query_id = 0,
    teleported_query: e.ke_query_id = 0,
    frame_local_query: e.ke_query_id = 0,
    tracker: e.ke_removal_tracker = 0,
    to_render: std.AutoHashMapUnmanaged(Entity, Entity) = .empty,
    to_main: std.AutoHashMapUnmanaged(Entity, Entity) = .empty,
    copies: std.ArrayList(Copy) = .empty,
    interps: std.ArrayList(*Interp) = .empty,
    customs: std.ArrayList(Custom) = .empty,
    sync_components: std.ArrayList(Cid) = .empty,
    sync_queries: std.ArrayList(e.ke_query_id) = .empty,
    history: ?*abi_schedule.c.ke_schedule = null,
    history_set: [1]abi_schedule.c.ke_schedule_set_id = .{0},
};

fn stateOf(self: ?*x.ke_extraction) ?*State {
    return @ptrCast(@alignCast((self orelse return null).handle orelse return null));
}

fn tag(ecs: *Ecs, name: [*:0]const u8) R.Error!Cid {
    var meta = std.mem.zeroes(e.ke_component_meta);
    if (ecs.component_lookup.?(ecs, name, &meta)) return meta.cid;
    var cid: Cid = 0;
    try R.check(ecs.component_register.?(ecs, &.{ .name = name, .size = 0, .alignment = 0 }, &cid));
    return cid;
}

fn tagQuery(ecs: *Ecs, cid: Cid) R.Error!e.ke_query_id {
    const terms = [_]e.ke_ecs_query_term{.{ .component = cid, .access = e.KE_ECS_ACCESS_READ }};
    var id: e.ke_query_id = 0;
    try R.check(ecs.query_register.?(ecs, &.{ .terms = &terms, .term_count = 1 }, &id));
    return id;
}

/// The entities a one-term query matches, appended to `out`.
fn matched(ecs: *Ecs, query: e.ke_query_id, out: *std.ArrayList(Entity)) R.Error!void {
    var capacity: usize = 16;
    while (true) {
        const segments = gpa.alloc(e.ke_ecs_segment, capacity) catch return error.OutOfMemory;
        defer gpa.free(segments);
        const columns = gpa.alloc(?*anyopaque, capacity) catch return error.OutOfMemory;
        defer gpa.free(columns);
        const components = gpa.alloc(Cid, capacity) catch return error.OutOfMemory;
        defer gpa.free(components);
        var count: usize = 0;
        try R.check(ecs.query_resolve.?(ecs, query, segments.ptr, capacity, &columns[0], &components[0], &count));
        if (count > capacity) {
            capacity = count;
            continue;
        }
        for (segments[0..count]) |segment| {
            if (segment.count == 0) continue;
            out.appendSlice(gpa, segment.entities.?[0..segment.count]) catch return error.OutOfMemory;
        }
        return;
    }
}

/// The byte offsets of the ENTITY fields of `fields`.
fn entityOffsets(fields: ?[*]const abi_ecs.c.ke_component_field, count: u32) R.Error![]u32 {
    var list: std.ArrayList(u32) = .empty;
    errdefer list.deinit(gpa);
    if (fields) |f| for (f[0..count]) |field| {
        if (field.type == abi_ecs_variant.c.KE_VARIANT_ENTITY) list.append(gpa, field.offset) catch return error.OutOfMemory;
    };
    return list.toOwnedSlice(gpa) catch error.OutOfMemory;
}

/// The size and the ENTITY field offsets of a render component, checked against the main one.
fn describe(s: *State, main_cid: Cid, render_cid: Cid) R.Error!struct { size: usize, offsets: []u32 } {
    const main_size = s.main.component_size.?(s.main, main_cid);
    const render_size = s.render.component_size.?(s.render, render_cid);
    if (main_size == 0 or main_size != render_size) {
        log.warn("extraction: components {d} and {d} are unknown or of different sizes ({d}, {d})", .{ main_cid, render_cid, main_size, render_size });
        return error.InvalidArgument;
    }
    var meta = std.mem.zeroes(e.ke_component_meta);
    const fields: ?[*]const abi_ecs.c.ke_component_field = if (s.render.component_meta.?(s.render, render_cid, &meta)) @ptrCast(meta.fields) else null;
    return .{ .size = render_size, .offsets = try entityOffsets(fields, if (fields != null) meta.field_count else 0) };
}

/// Slot `extract_copy`.
fn extractCopy(self: ?*x.ke_extraction, main_cid: Cid, render_cid: Cid) callconv(.c) Result {
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    for (s.copies.items) |c| if (c.main == main_cid and c.render == render_cid) return R.ok;
    const d = describe(s, main_cid, render_cid) catch |err| return R.code(err);
    s.copies.append(gpa, .{ .main = main_cid, .render = render_cid, .size = d.size, .entity_offsets = d.offsets }) catch {
        gpa.free(d.offsets);
        return R.code(error.OutOfMemory);
    };
    return R.ok;
}

/// Slot `extract_interpolate`.
fn extractInterpolate(self: ?*x.ke_extraction, main_cid: Cid, previous_cid: Cid, render_cid: Cid, blend: x.ke_extraction_interpolate_fn, user: ?*anyopaque) callconv(.c) Result {
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    if (blend == null) return R.code(error.InvalidArgument);
    if (s.main.component_size.?(s.main, previous_cid) != s.main.component_size.?(s.main, main_cid)) {
        log.warn("extraction: the previous component {d} is not the size of {d}", .{ previous_cid, main_cid });
        return R.code(error.InvalidArgument);
    }
    const d = describe(s, main_cid, render_cid) catch |err| return R.code(err);
    const i = gpa.create(Interp) catch {
        gpa.free(d.offsets);
        return R.code(error.OutOfMemory);
    };
    i.* = .{ .main = main_cid, .previous = previous_cid, .render = render_cid, .size = d.size, .entity_offsets = d.offsets, .blend = blend, .user = user };
    i.terms = .{ .{ .component = main_cid, .access = e.KE_ECS_ACCESS_READ }, .{ .component = previous_cid, .access = e.KE_ECS_ACCESS_WRITE } };
    i.queries = .{.{ .terms = &i.terms, .term_count = 2 }};
    s.interps.append(gpa, i) catch {
        freeInterp(i);
        return R.code(error.OutOfMemory);
    };
    if (s.history != null) registerHistory(s, i) catch |err| {
        _ = s.interps.pop();
        freeInterp(i);
        return R.code(err);
    };
    return R.ok;
}

/// Slot `extract_custom`.
fn extractCustom(self: ?*x.ke_extraction, extract_fn: x.ke_extraction_custom_fn, user: ?*anyopaque) callconv(.c) Result {
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    if (extract_fn == null) return R.code(error.InvalidArgument);
    s.customs.append(gpa, .{ .extract = extract_fn, .user = user }) catch return R.code(error.OutOfMemory);
    return R.ok;
}

/// Slot `render_entity`.
fn renderEntity(self: ?*x.ke_extraction, main_entity: Entity, out_entity: ?*Entity) callconv(.c) Result {
    const out = out_entity orelse return R.code(error.InvalidArgument);
    out.* = no_entity;
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    out.* = s.to_render.get(main_entity) orelse return R.code(error.NotFound);
    return R.ok;
}

/// Slot `main_entity`.
fn mainEntity(self: ?*x.ke_extraction, render_entity: Entity, out_entity: ?*Entity) callconv(.c) Result {
    const out = out_entity orelse return R.code(error.InvalidArgument);
    out.* = no_entity;
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    out.* = s.to_main.get(render_entity) orelse return R.code(error.NotFound);
    return R.ok;
}

/// Slot `sync_component`: a query of the component, registered once.
fn syncComponent(self: ?*x.ke_extraction, main_cid: Cid) callconv(.c) Result {
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    if (std.mem.indexOfScalar(Cid, s.sync_components.items, main_cid) != null) return R.ok;
    const query = tagQuery(s.main, main_cid) catch |err| {
        log.warn("extraction: component {d} cannot be synced", .{main_cid});
        return R.code(err);
    };
    s.sync_components.append(gpa, main_cid) catch return R.code(error.OutOfMemory);
    s.sync_queries.append(gpa, query) catch {
        _ = s.sync_components.pop();
        return R.code(error.OutOfMemory);
    };
    return R.ok;
}

fn unpair(s: *State, main_entity: Entity) void {
    const r = s.to_render.fetchRemove(main_entity) orelse return;
    _ = s.to_main.remove(r.value);
    _ = s.render.entity_destroy.?(s.render, r.value);
}

fn remap(s: *State, bytes: [*]u8, offsets: []const u32) void {
    for (offsets) |offset| {
        const field: *align(1) Entity = @ptrCast(bytes + offset);
        field.* = s.to_render.get(field.*) orelse no_entity;
    }
}

fn renderSlot(s: *State, pair: Entity, cid: Cid) R.Error![*]u8 {
    if (s.render.component_get.?(s.render, pair, cid)) |p| return @ptrCast(p);
    var data: ?*anyopaque = null;
    try R.check(s.render.component_add.?(s.render, pair, cid, &data));
    return @ptrCast(data orelse return error.General);
}

fn contains(list: []const Entity, entity: Entity) bool {
    return std.mem.indexOfScalar(Entity, list, entity) != null;
}

fn extractAll(s: *State, alpha: f32) R.Error!void {
    var scratch: std.ArrayList(Entity) = .empty;
    defer scratch.deinit(gpa);

    try matched(s.render, s.frame_local_query, &scratch);
    for (scratch.items) |entity| {
        if (s.to_main.fetchRemove(entity)) |m| _ = s.to_render.remove(m.value);
        try R.check(s.render.entity_destroy.?(s.render, entity));
    }

    var lost: [64]Entity = undefined;
    while (true) {
        var count: usize = 0;
        try R.check(s.main.removals.?(s.main, s.tracker, &lost, lost.len, &count));
        for (lost[0..@min(count, lost.len)]) |entity| unpair(s, entity);
        if (count <= lost.len) break;
    }

    scratch.clearRetainingCapacity();
    try matched(s.main, s.synced_query, &scratch);
    for (s.sync_queries.items) |query| try matched(s.main, query, &scratch);
    var wanted: std.AutoHashMapUnmanaged(Entity, void) = .empty;
    defer wanted.deinit(gpa);
    for (scratch.items) |entity| wanted.put(gpa, entity, {}) catch return error.OutOfMemory;
    var gone: std.ArrayList(Entity) = .empty;
    defer gone.deinit(gpa);
    var paired = s.to_render.keyIterator();
    while (paired.next()) |entity| if (!wanted.contains(entity.*)) gone.append(gpa, entity.*) catch return error.OutOfMemory;
    for (gone.items) |entity| unpair(s, entity);
    var fresh: std.ArrayList(Entity) = .empty;
    defer fresh.deinit(gpa);
    for (scratch.items) |entity| {
        if (s.to_render.contains(entity)) continue;
        var pair: Entity = no_entity;
        try R.check(s.render.entity_create.?(s.render, &pair));
        s.to_render.put(gpa, entity, pair) catch return error.OutOfMemory;
        s.to_main.put(gpa, pair, entity) catch return error.OutOfMemory;
        fresh.append(gpa, entity) catch return error.OutOfMemory;
    }

    var interpolated: std.ArrayList(Entity) = .empty;
    defer interpolated.deinit(gpa);
    var teleported: std.ArrayList(Entity) = .empty;
    defer teleported.deinit(gpa);
    if (s.interps.items.len > 0) {
        try matched(s.main, s.interpolated_query, &interpolated);
        try matched(s.main, s.teleported_query, &teleported);
    }

    var it = s.to_render.iterator();
    while (it.next()) |kv| {
        const entity = kv.key_ptr.*;
        const pair = kv.value_ptr.*;
        for (s.copies.items) |c| {
            const src: ?[*]const u8 = @ptrCast(s.main.component_get.?(s.main, entity, c.main));
            if (src) |from| {
                const to = try renderSlot(s, pair, c.render);
                @memcpy(to[0..c.size], from[0..c.size]);
                remap(s, to, c.entity_offsets);
            } else if (s.render.component_get.?(s.render, pair, c.render) != null) {
                try R.check(s.render.component_remove.?(s.render, pair, c.render));
            }
        }
        for (s.interps.items) |i| {
            const current: [*]const u8 = @ptrCast(s.main.component_get.?(s.main, entity, i.main) orelse {
                if (s.render.component_get.?(s.render, pair, i.render) != null) try R.check(s.render.component_remove.?(s.render, pair, i.render));
                continue;
            });
            var previous: ?[*]u8 = @ptrCast(s.main.component_get.?(s.main, entity, i.previous));
            const reset = previous == null or contains(fresh.items, entity) or contains(teleported.items, entity);
            if (previous == null) {
                var data: ?*anyopaque = null;
                try R.check(s.main.component_add.?(s.main, entity, i.previous, &data));
                previous = @ptrCast(data orelse return error.General);
            }
            if (reset) @memcpy(previous.?[0..i.size], current[0..i.size]);
            const to = try renderSlot(s, pair, i.render);
            if (contains(interpolated.items, entity)) i.blend.?(i.user, previous.?, current, alpha, to) else @memcpy(to[0..i.size], current[0..i.size]);
            remap(s, to, i.entity_offsets);
        }
    }
    for (teleported.items) |entity| try R.check(s.main.component_remove.?(s.main, entity, s.teleported));

    for (s.customs.items) |c| try R.check(c.extract.?(c.user, &s.api, s.main, s.render));
}

/// Slot `extract`.
fn extract(self: ?*x.ke_extraction, alpha: f32) callconv(.c) Result {
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    extractAll(s, alpha) catch |err| {
        log.warn("extraction failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

/// Slot `run`: the render stage.
fn run(self: ?*x.ke_extraction, dt: f32, out_completion: ?*?*abi_completion.c.ke_completion) callconv(.c) Result {
    const out = out_completion orelse return R.code(error.InvalidArgument);
    out.* = null;
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    const extracted = extract(&s.api, s.scheduler.fixed_alpha.?(s.scheduler));
    if (extracted != R.ok) return extracted;
    return s.render_schedule.run.?(s.render_schedule, dt, out);
}

/// The history system of one interpolation: copies each entity's current value into its previous one.
fn historySystem(ctx: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) Result {
    const i: *Interp = @ptrCast(@alignCast(user orelse return R.code(error.InvalidArgument)));
    var count: usize = 0;
    const segments = ctx.?.view.?(ctx, 0, &count) orelse return R.ok;
    for (segments[0..count]) |segment| {
        if (segment.count == 0) continue;
        const from: [*]const u8 = @ptrCast(segment.columns.?[0]);
        const to: [*]u8 = @ptrCast(segment.columns.?[1]);
        @memcpy(to[0 .. segment.count * i.size], from[0 .. segment.count * i.size]);
    }
    return R.ok;
}

fn registerHistory(s: *State, i: *Interp) R.Error!void {
    const schedule = s.history.?;
    const desc: abi_schedule.c.ke_schedule_system_desc = .{
        .name = "extraction.history",
        .user_data = i,
        .execute = historySystem,
        .queries = &i.queries,
        .query_count = 1,
        .sets = &s.history_set,
        .set_count = 1,
    };
    try R.check(schedule.register_system.?(schedule, &desc, &i.system));
    i.registered = true;
}

fn detachHistory(s: *State) void {
    const schedule = s.history orelse return;
    for (s.interps.items) |i| if (i.registered) {
        _ = schedule.unregister_system.?(schedule, i.system);
        i.registered = false;
    };
    s.history = null;
}

/// Slot `attach` of the history module: one system per interpolation in the fixed schedule's
/// fixed_pre_update set; a failure leaves none registered.
fn historyAttach(self: ?*abi_module.c.ke_module, targets_in: ?*const abi_module.c.ke_module_targets) callconv(.c) Result {
    const s: *State = @ptrCast(@alignCast((self orelse return R.code(error.InvalidArgument)).handle));
    const targets = targets_in orelse return R.code(error.InvalidArgument);
    if (s.history != null) return R.code(error.NotSupported);
    s.history = @ptrCast(targets.fixed orelse return R.code(error.InvalidArgument));
    s.history_set = .{targets.fixed_pre_update_set};
    for (s.interps.items) |i| registerHistory(s, i) catch |err| {
        detachHistory(s);
        log.warn("attaching the extraction history failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

/// Slot `detach` of the history module.
fn historyDetach(self: ?*abi_module.c.ke_module) callconv(.c) void {
    detachHistory(@ptrCast(@alignCast((self orelse return).handle)));
}

/// The history module handle's `destroy`: detaches; the state stays with the extraction.
fn historyDestroy(self: ?*abi_module.c.ke_module) callconv(.c) void {
    historyDetach(self);
}

export fn ke_extraction_history_create(extraction: ?*x.ke_extraction, out_module: ?*abi_module.c.ke_module_handle) callconv(.c) Result {
    const out = out_module orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_module.c.ke_module_handle);
    const given = extraction orelse return R.code(error.InvalidArgument);
    if (given.extract != &extract) {
        log.warn("extraction history: the extraction was not created by this library", .{});
        return R.code(error.InvalidArgument);
    }
    const s = stateOf(given) orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = &s.module, .destroy = historyDestroy };
    return R.ok;
}

fn freeInterp(i: *Interp) void {
    gpa.free(i.entity_offsets);
    gpa.destroy(i);
}

/// The handle's `destroy`: detaches the history, destroys every pair and frees the state.
fn destroy(self: ?*x.ke_extraction) callconv(.c) void {
    const s = stateOf(self) orelse return;
    detachHistory(s);
    var it = s.to_main.keyIterator();
    while (it.next()) |pair| _ = s.render.entity_destroy.?(s.render, pair.*);
    s.to_render.deinit(gpa);
    s.to_main.deinit(gpa);
    for (s.copies.items) |c| gpa.free(c.entity_offsets);
    s.copies.deinit(gpa);
    for (s.interps.items) |i| freeInterp(i);
    s.interps.deinit(gpa);
    s.customs.deinit(gpa);
    s.sync_components.deinit(gpa);
    s.sync_queries.deinit(gpa);
    gpa.destroy(s);
}

export fn ke_extraction_create(
    main_in: ?*Ecs,
    render_in: ?*Ecs,
    scheduler_in: ?*abi_scheduler.c.ke_scheduler,
    render_schedule_in: ?*abi_schedule.c.ke_schedule,
    out_extraction: ?*x.ke_extraction_handle,
) callconv(.c) Result {
    const out = out_extraction orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(x.ke_extraction_handle);
    out.* = create(
        main_in orelse return R.code(error.InvalidArgument),
        render_in orelse return R.code(error.InvalidArgument),
        scheduler_in orelse return R.code(error.InvalidArgument),
        render_schedule_in orelse return R.code(error.InvalidArgument),
    ) catch |err| {
        log.warn("creating the extraction failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn create(main: *Ecs, render: *Ecs, scheduler: *abi_scheduler.c.ke_scheduler, render_schedule: *abi_schedule.c.ke_schedule) R.Error!x.ke_extraction_handle {
    const s = gpa.create(State) catch return error.OutOfMemory;
    errdefer gpa.destroy(s);
    s.* = .{
        .api = .{
            .sync_component = syncComponent,
            .extract_copy = extractCopy,
            .extract_interpolate = extractInterpolate,
            .extract_custom = extractCustom,
            .render_entity = renderEntity,
            .main_entity = mainEntity,
            .extract = extract,
            .run = run,
        },
        .main = main,
        .render = render,
        .scheduler = scheduler,
        .render_schedule = render_schedule,
    };
    s.api.handle = s;
    s.executable.user = &s.api;
    s.module = .{ .handle = s, .attach = historyAttach, .detach = historyDetach };
    s.synced = try tag(main, x.KE_COMPONENT_NAME_RENDER_SYNCED);
    s.interpolated = try tag(main, x.KE_COMPONENT_NAME_INTERPOLATED);
    s.teleported = try tag(main, x.KE_COMPONENT_NAME_TELEPORTED);
    s.frame_local = try tag(render, x.KE_COMPONENT_NAME_FRAME_LOCAL);
    s.synced_query = try tagQuery(main, s.synced);
    s.interpolated_query = try tagQuery(main, s.interpolated);
    s.teleported_query = try tagQuery(main, s.teleported);
    s.frame_local_query = try tagQuery(render, s.frame_local);
    try R.check(main.removal_track.?(main, s.synced, &s.tracker));
    return .{ .ref = &s.api, .destroy = destroy };
}

/// The extraction as a scheduler runs it: `user` is the extraction itself, the name completed_since knows it by.
fn runAsExecutable(user: ?*anyopaque, dt: f32, out_completion: ?*?*abi_completion.c.ke_completion) callconv(.c) Result {
    return run(@ptrCast(@alignCast(user orelse return R.code(error.InvalidArgument))), dt, out_completion);
}

/// The vtable of each contract the extraction's part provides: the extraction, then the executable.
fn provided(instance: ?*anyopaque, index: usize) callconv(.c) ?*anyopaque {
    const s = stateOf(@ptrCast(@alignCast(instance))) orelse return null;
    return if (index == 0) &s.api else &s.executable;
}

pub const parts = [_]abi_part.c.ke_part{
    part.of(ke_extraction_create, .{ .name = "extraction", .slots = &.{ "main", "render", "scheduler", "render_schedule" }, .also = &.{"ke_scheduler_executable"}, .provided = provided, .set_log = @ptrCast(&@import("log").Destination("ke_extraction_default").setLogCallback) }),
};

/// The library's parts.
export fn ke_extraction_default_parts(out_count: ?*usize) callconv(.c) ?*const abi_part.c.ke_part {
    if (out_count) |n| n.* = parts.len;
    return &parts[0];
}

test {
    _ = @import("extraction_default_test.zig");
}
