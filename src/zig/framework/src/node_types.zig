//! Node types: each behaviour of a registered type runs as one exclusive system of its phase,
//! walking the nodes of the type through a `ke_node_ctx`, and events are entities that live from
//! the tick they are raised in to the next PreUpdate.

const std = @import("std");

const abi_ecs = @import("abi_ecs");
const abi_framework = @import("abi_framework");
const abi_framework_components = @import("abi_framework_components");
const abi_input_actions = @import("abi_input_actions");
const abi_part = @import("abi_part");
const abi_ecs_variant = @import("abi_ecs_variant");
const abi_result = @import("abi_result");
const abi_engine_node_types = @import("abi_engine_node_types");
const part = @import("part");
const abi_schedule = @import("abi_schedule");
const abi_scheduler = @import("abi_scheduler");
const abi_scene_tree = @import("abi_scene_tree");
const R = @import("result").Result(.{});
const log = std.log.scoped(.framework);
const heap = @import("heap");
const fields_apply = @import("component_fields_apply.zig");

const Entity = abi_ecs.c.ke_entity;
const Cid = abi_ecs.c.ke_component_id;
const invalid = abi_ecs.c.KE_ENTITY_INVALID;
const status_name = "node_status";
const stamp_name = "node_event_stamp";

/// The number of the schedule run an event was raised in, which decides when it expires.
const EventStamp = extern struct { sequence: u64 };
const base_type_name = "node";
const scene_slot_name = "scene_slot";
const scene_slot_path_field = "path";
const prototype_alignment: std.mem.Alignment = .@"16";

const NodeStatus = extern struct { readied: u8, exiting: u8 = 0, exited: u8 = 0, has_exit: u8 = 0 };

const Kind = enum { ready, update, fixed_update, on, exit };

/// One registered behaviour: the system it runs as, and the query that system reads through. The
/// scheduler keeps its address as the system's user data and reads `terms` while registering it.
const Behaviour = struct {
    owner: *Type,
    kind: Kind,
    run: abi_framework.c.ke_node_behaviour_fn,
    event: ?*Event = null,
    system: abi_schedule.c.ke_schedule_system_id = 0,
    registered: bool = false,
    name: [:0]u8,
    terms: []abi_ecs.c.ke_ecs_query_term,
    event_terms: [1]abi_ecs.c.ke_ecs_query_term = undefined,
    queries: [2]abi_ecs.c.ke_ecs_query_desc = undefined,
};

/// A registered node type: its tag, the component ids its nodes carry, the fields first when it
/// has them, with the size and the default-seeded bytes of each, and the behaviours it runs. A
/// behaviour's query reads the tag first, so a component's column is its index plus one.
const Type = struct {
    state: *State,
    tag: Cid,
    has_fields: bool,
    has_exit: bool = false,
    columns: []Cid,
    sizes: []usize,
    prototypes: [][]align(16) u8,
    user_data: ?*anyopaque,
    behaviours: std.ArrayList(*Behaviour) = .empty,
};

/// A registered event type, and the system of the pre-update set that destroys the events of the
/// last tick.
const Event = struct {
    owner: *State,
    cid: Cid,
    size: usize,
    system: abi_schedule.c.ke_schedule_system_id = 0,
    registered: bool = false,
    name: [:0]u8,
    terms: [2]abi_ecs.c.ke_ecs_query_term = undefined,
    queries: [1]abi_ecs.c.ke_ecs_query_desc = undefined,
};

/// Created by `ke_node_types_create` and freed by `vtDestroy`, which detaches first. It owns the
/// types and events, whose addresses the schedules hold as user data. While `attached`, a ready,
/// exit and event-clearing system runs in `first`, a fixed update in `fixed`, an update in `main`,
/// and an event and reaping system in `post`, each in the set of its hook; `loop` takes the
/// requests to exit. The systems module the second factory creates is this state's.
const State = struct {
    api: abi_framework.c.ke_node_types,
    loop: *abi_scheduler.c.ke_scheduler,
    attached: bool = false,
    first: *abi_schedule.c.ke_schedule = undefined,
    fixed: *abi_schedule.c.ke_schedule = undefined,
    main: *abi_schedule.c.ke_schedule = undefined,
    post: *abi_schedule.c.ke_schedule = undefined,
    pre_update: [1]abi_schedule.c.ke_schedule_set_id = .{0},
    update: [1]abi_schedule.c.ke_schedule_set_id = .{0},
    fixed_update: [1]abi_schedule.c.ke_schedule_set_id = .{0},
    post_update: [1]abi_schedule.c.ke_schedule_set_id = .{0},
    ecs: *abi_ecs.c.ke_ecs,
    tree: *abi_scene_tree.c.ke_scene_tree,
    actions: ?*abi_input_actions.c.ke_input_actions,
    status_cid: Cid,
    stamp_cid: Cid,
    name_cid: Cid,
    types: std.ArrayList(*Type) = .empty,
    events: std.ArrayList(*Event) = .empty,
    action_ids: std.StringHashMapUnmanaged(i32) = .empty,
    reap: abi_schedule.c.ke_schedule_system_id = 0,
    reap_terms: [1]abi_ecs.c.ke_ecs_query_term = undefined,
    reap_queries: [1]abi_ecs.c.ke_ecs_query_desc = undefined,
};

fn stateOf(self: ?*abi_framework.c.ke_node_types) ?*State {
    const api = self orelse return null;
    return @ptrCast(@alignCast(api.handle orelse return null));
}

fn findType(s: *State, cid: Cid) ?*Type {
    for (s.types.items) |t| if (t.tag == cid) return t;
    return null;
}

fn findEvent(s: *State, cid: Cid) ?*Event {
    for (s.events.items) |e| if (e.cid == cid) return e;
    return null;
}

/// The cursor a behaviour's `ke_node_ctx` walks: the segments of the type's query, and for an on
/// handler the segments of the event query, which the walk takes as the outer loop.
const Walk = struct {
    api: abi_framework.c.ke_node_ctx,
    behaviour: *Behaviour,
    segs: []const abi_ecs.c.ke_ecs_segment,
    seg: usize = 0,
    row: usize = 0,
    started: bool = false,
    events: []const abi_ecs.c.ke_ecs_segment = &.{},
    ev_seg: usize = 0,
    ev_row: usize = 0,
};

fn walkOf(ctx: ?*abi_framework.c.ke_node_ctx) ?*Walk {
    const api = ctx orelse return null;
    return @ptrCast(@alignCast(api.handle orelse return null));
}

fn column(w: *Walk, index: usize, size: usize) ?*anyopaque {
    const seg = w.segs[w.seg];
    const base: [*]u8 = @ptrCast(seg.columns.?[index] orelse return null);
    return base + w.row * size;
}

fn advanceNode(w: *Walk) bool {
    if (w.started) w.row += 1 else w.started = true;
    while (w.seg < w.segs.len and w.row >= w.segs[w.seg].count) {
        w.seg += 1;
        w.row = 0;
    }
    return w.seg < w.segs.len;
}

fn advanceEvent(w: *Walk) bool {
    w.ev_row += 1;
    while (w.ev_seg < w.events.len and w.ev_row >= w.events[w.ev_seg].count) {
        w.ev_seg += 1;
        w.ev_row = 0;
    }
    return w.ev_seg < w.events.len;
}

fn eventAt(w: *Walk) ?*const anyopaque {
    const seg = w.events[w.ev_seg];
    const base: [*]const u8 = @ptrCast(seg.columns.?[0] orelse return null);
    return base + w.ev_row * w.behaviour.event.?.size;
}

/// Slot `next`. Moves to the next node of the type, past the nodes leaving the tree; a ready
/// behaviour skips the nodes already readied and marks each one it moves to, an exit behaviour
/// moves only to the nodes leaving and marks each; an on handler moves through every node for one
/// event, then to the next event.
fn next(ctx: ?*abi_framework.c.ke_node_ctx) callconv(.c) bool {
    const w = walkOf(ctx) orelse return false;
    while (true) {
        if (w.behaviour.kind == .on) {
            if (w.ev_seg >= w.events.len) return false;
            if (!advanceNode(w)) {
                if (!advanceEvent(w)) return false;
                w.seg = 0;
                w.row = 0;
                w.started = false;
                continue;
            }
            w.api.event = eventAt(w);
        } else if (!advanceNode(w)) {
            w.api.self = invalid;
            w.api.fields = null;
            return false;
        }
        const status: *NodeStatus = @ptrCast(column(w, w.behaviour.owner.columns.len + 1, @sizeOf(NodeStatus)) orelse continue);
        switch (w.behaviour.kind) {
            .exit => {
                if (status.exiting == 0 or status.exited != 0) continue;
                status.exited = 1;
            },
            .ready => {
                if (status.exiting != 0 or status.readied != 0) continue;
                status.readied = 1;
            },
            else => if (status.exiting != 0) continue,
        }
        w.api.self = w.segs[w.seg].entities.?[w.row];
        const t = w.behaviour.owner;
        w.api.fields = if (t.has_fields) column(w, 1, t.sizes[0]) else null;
        return true;
    }
}

/// Slot `get`. The current node's component `cid`, found among the columns of the type.
fn get(ctx: ?*abi_framework.c.ke_node_ctx, cid: Cid) callconv(.c) ?*anyopaque {
    const w = walkOf(ctx) orelse return null;
    if (w.api.self == invalid) return null;
    for (w.behaviour.owner.columns, w.behaviour.owner.sizes, 0..) |c, size, i| if (c == cid) return column(w, i + 1, size);
    return null;
}

/// Slot `component`. Asks the ecs.
fn component(ctx: ?*abi_framework.c.ke_node_ctx, node: Entity, cid: Cid) callconv(.c) ?*anyopaque {
    const w = walkOf(ctx) orelse return null;
    const s = w.behaviour.owner.state;
    return s.ecs.component_get.?(s.ecs, node, cid);
}

/// Slot `parent`. Asks the scene tree.
fn parent(ctx: ?*abi_framework.c.ke_node_ctx, node: Entity) callconv(.c) Entity {
    const w = walkOf(ctx) orelse return invalid;
    const s = w.behaviour.owner.state;
    return s.tree.parent.?(s.tree, node);
}

/// Slot `child`. Walks the children of `node` in the scene tree and compares their name component.
fn child(ctx: ?*abi_framework.c.ke_node_ctx, node: Entity, name: ?[*:0]const u8) callconv(.c) Entity {
    const w = walkOf(ctx) orelse return invalid;
    const wanted = std.mem.span(name orelse return invalid);
    const s = w.behaviour.owner.state;
    var c = s.tree.first_child.?(s.tree, node);
    while (c != invalid) : (c = s.tree.next_sibling.?(s.tree, c)) {
        const n: *const abi_framework_components.c.ke_name_component = @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, c, s.name_cid) orelse continue));
        if (std.mem.eql(u8, std.mem.sliceTo(&n.name, 0), wanted)) return c;
    }
    return invalid;
}

/// Slot `first_child`. Asks the scene tree.
fn firstChild(ctx: ?*abi_framework.c.ke_node_ctx, node: Entity) callconv(.c) Entity {
    const w = walkOf(ctx) orelse return invalid;
    const s = w.behaviour.owner.state;
    return s.tree.first_child.?(s.tree, node);
}

/// Slot `next_sibling`. Asks the scene tree.
fn nextSibling(ctx: ?*abi_framework.c.ke_node_ctx, node: Entity) callconv(.c) Entity {
    const w = walkOf(ctx) orelse return invalid;
    const s = w.behaviour.owner.state;
    return s.tree.next_sibling.?(s.tree, node);
}

/// Slot `ancestor`. Walks the parents in the scene tree and asks the ecs for the component.
fn ancestor(ctx: ?*abi_framework.c.ke_node_ctx, node: Entity, held: Cid) callconv(.c) Entity {
    const w = walkOf(ctx) orelse return invalid;
    const s = w.behaviour.owner.state;
    var at = s.tree.parent.?(s.tree, node);
    while (at != invalid) : (at = s.tree.parent.?(s.tree, at)) {
        if (s.ecs.component_get.?(s.ecs, at, held) != null) return at;
    }
    return invalid;
}

/// Slot `axis`. Asks the input actions, 0 without them.
fn axis(ctx: ?*abi_framework.c.ke_node_ctx, action: ?*abi_framework.c.ke_action_ref) callconv(.c) f32 {
    const w = walkOf(ctx) orelse return 0;
    const actions = w.behaviour.owner.state.actions orelse return 0;
    const id = resolve(actions, action orelse return 0) orelse return 0;
    return actions.get_axis1d.?(actions, id);
}

/// Slot `pressed`. Asks the input actions, false without them.
fn pressed(ctx: ?*abi_framework.c.ke_node_ctx, action: ?*abi_framework.c.ke_action_ref) callconv(.c) bool {
    const w = walkOf(ctx) orelse return false;
    const actions = w.behaviour.owner.state.actions orelse return false;
    const id = resolve(actions, action orelse return false) orelse return false;
    return actions.was_action_pressed.?(actions, id);
}

/// Looks the reference's name up once and keeps the answer in it; null for a name no map holds.
fn resolve(actions: *abi_input_actions.c.ke_input_actions, action: *abi_framework.c.ke_action_ref) ?i32 {
    if (!action.resolved) {
        action.id = actions.get_action_id.?(actions, @ptrCast(&action.name));
        action.resolved = true;
        if (action.id < 0) log.warn("node types: no input action is named {s}", .{std.mem.sliceTo(&action.name, 0)});
    }
    return if (action.id < 0) null else action.id;
}

fn spawnNode(s: *State, commands: *abi_ecs.c.ke_ecs_commands, type_cid: Cid, name: ?[*:0]const u8, under: Entity, components_in: ?[*]const abi_framework.c.ke_node_component, count: u32, out: *Entity) abi_result.c.ke_result {
    const t = findType(s, type_cid) orelse {
        log.warn("node types: spawning a type never registered ({d})", .{type_cid});
        return R.code(error.NotFound);
    };
    const components: []const abi_framework.c.ke_node_component = if (count == 0) &.{} else (components_in orelse return R.code(error.InvalidArgument))[0..count];
    for (components) |given| {
        const at = std.mem.indexOfScalar(Cid, t.columns, given.component) orelse {
            log.warn("node types: a spawn gives component {d}, which its type does not carry", .{given.component});
            return R.code(error.InvalidArgument);
        };
        if (given.data == null or given.size != t.sizes[at]) {
            log.warn("node types: a spawn gives component {d} {d} bytes, not its {d}", .{ given.component, given.size, t.sizes[at] });
            return R.code(error.InvalidArgument);
        }
    }
    var node: Entity = invalid;
    var rc = s.tree.create_node_deferred.?(s.tree, name, under, commands, &node);
    if (rc != R.ok) return rc;
    rc = commands.attach.?(commands, node, t.tag, null, 0);
    if (rc != R.ok) return rc;
    for (t.columns, t.prototypes) |c, proto| {
        var data: ?*const anyopaque = proto.ptr;
        for (components) |given| {
            if (given.component == c) data = given.data;
        }
        rc = commands.attach.?(commands, node, c, data, proto.len);
        if (rc != R.ok) return rc;
    }
    const status: NodeStatus = .{ .readied = 0, .has_exit = @intFromBool(t.has_exit) };
    rc = commands.attach.?(commands, node, s.status_cid, &status, @sizeOf(NodeStatus));
    if (rc != R.ok) return rc;
    out.* = node;
    return R.ok;
}

fn lookupMeta(s: *State, name: [*:0]const u8) ?abi_ecs.c.ke_component_meta {
    var meta = std.mem.zeroes(abi_ecs.c.ke_component_meta);
    return if (s.ecs.component_lookup.?(s.ecs, name, &meta)) meta else null;
}

fn writeNamed(s: *State, memory: *anyopaque, meta: abi_ecs.c.ke_component_meta, field: [*:0]const u8, value: abi_ecs_variant.c.ke_variant) bool {
    const table = meta.fields orelse return false;
    var entry = [1]abi_ecs_variant.c.ke_variant_table_entry{.{ .key = field, .value = value, .consumed = false }};
    if (fields_apply.apply(s.ecs, memory, &entry, 1, @ptrCast(table), meta.field_count) != null) return false;
    return entry[0].consumed;
}

/// Slot `change_scene`. Finds the nearest ancestor holding a scene slot and writes the path
/// through the slot's field table.
fn changeScene(ctx: ?*abi_framework.c.ke_node_ctx, path_in: ?[*:0]const u8) callconv(.c) abi_result.c.ke_result {
    const w = walkOf(ctx) orelse return R.code(error.InvalidArgument);
    const path = path_in orelse return R.code(error.InvalidArgument);
    const s = w.behaviour.owner.state;
    const meta = lookupMeta(s, scene_slot_name) orelse {
        log.warn("node types: changing scene with no scene slot registered", .{});
        return R.code(error.NotFound);
    };
    const holder = ancestor(ctx, w.api.self, meta.cid);
    if (holder == invalid) {
        log.warn("node types: changing scene from a node no scene slot holds", .{});
        return R.code(error.NotFound);
    }
    const slot = s.ecs.component_get.?(s.ecs, holder, meta.cid) orelse return R.code(error.NotFound);
    if (std.mem.len(path) >= slotPathCapacity(meta)) {
        log.warn("node types: scene path {s} is longer than a slot holds", .{path});
        return R.code(error.InvalidArgument);
    }
    const value: abi_ecs_variant.c.ke_variant = .{ .type = abi_ecs_variant.c.KE_VARIANT_STRING, .unnamed_0 = .{ .s = path } };
    return if (writeNamed(s, slot, meta, scene_slot_path_field, value)) R.ok else R.code(error.InvalidArgument);
}

fn slotPathCapacity(meta: abi_ecs.c.ke_component_meta) usize {
    const table: [*]const abi_ecs.c.ke_component_field = @ptrCast(meta.fields orelse return 0);
    for (table[0..meta.field_count]) |f| {
        if (std.mem.eql(u8, std.mem.span(f.name.?), scene_slot_path_field)) return f.size;
    }
    return 0;
}

/// Slot `spawn` of the ctx: the node types' spawn with the behaviour's commands.
fn spawn(ctx: ?*abi_framework.c.ke_node_ctx, type_cid: Cid, name: ?[*:0]const u8, under: Entity, components: ?[*]const abi_framework.c.ke_node_component, count: u32, out_node: ?*Entity) callconv(.c) abi_result.c.ke_result {
    const w = walkOf(ctx) orelse return R.code(error.InvalidArgument);
    const out = out_node orelse return R.code(error.InvalidArgument);
    const commands = w.api.commands orelse return R.code(error.InvalidArgument);
    return spawnNode(w.behaviour.owner.state, commands, type_cid, name, under, components, count, out);
}

/// Slot `destroy`. Records the destruction through the scene tree.
fn destroy(ctx: ?*abi_framework.c.ke_node_ctx, node: Entity) callconv(.c) abi_result.c.ke_result {
    const w = walkOf(ctx) orelse return R.code(error.InvalidArgument);
    const s = w.behaviour.owner.state;
    if (statusOf(s, node) == null) return s.tree.destroy_node_deferred.?(s.tree, node, w.api.commands);
    markLeaving(s, node);
    return R.ok;
}

fn statusOf(s: *State, node: Entity) ?*NodeStatus {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, node, s.status_cid) orelse return null));
}

fn markLeaving(s: *State, node: Entity) void {
    if (statusOf(s, node)) |status| status.exiting = 1;
    var at = s.tree.first_child.?(s.tree, node);
    while (at != invalid) : (at = s.tree.next_sibling.?(s.tree, at)) markLeaving(s, at);
}

fn leavingDone(s: *State, node: Entity) bool {
    if (statusOf(s, node)) |status| {
        if (status.exiting == 0 or (status.has_exit != 0 and status.exited == 0)) return false;
    }
    var at = s.tree.first_child.?(s.tree, node);
    while (at != invalid) : (at = s.tree.next_sibling.?(s.tree, at)) if (!leavingDone(s, at)) return false;
    return true;
}

/// The PostUpdate system that removes the nodes left: it records the destruction of each node
/// leaving the tree whose parent is not leaving, once every node of its subtree has run its exit.
fn reapLeaving(sys: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const s: *State = @ptrCast(@alignCast(user orelse return R.ok));
    for (viewOf(sys, 0)) |seg| {
        const statuses: [*]const NodeStatus = @ptrCast(@alignCast(seg.columns.?[0] orelse continue));
        for (seg.entities.?[0..seg.count], statuses[0..seg.count]) |node, status| {
            if (status.exiting == 0) continue;
            const up = s.tree.parent.?(s.tree, node);
            if (up != invalid) if (statusOf(s, up)) |above| if (above.exiting != 0) continue;
            if (!leavingDone(s, node)) continue;
            const rc = s.tree.destroy_node_deferred.?(s.tree, node, sys.?.commands);
            if (rc != R.ok) return rc;
        }
    }
    return R.ok;
}

/// Slot `find_type` of the ctx: the node types' find_type.
fn ctxFindType(ctx: ?*abi_framework.c.ke_node_ctx, name: ?[*:0]const u8, out_type: ?*Cid) callconv(.c) abi_result.c.ke_result {
    const w = walkOf(ctx) orelse return R.code(error.InvalidArgument);
    return vtFindType(&w.behaviour.owner.state.api, name, out_type);
}

/// Slot `find_component` of the ctx: the node types' find_component.
fn ctxFindComponent(ctx: ?*abi_framework.c.ke_node_ctx, name: ?[*:0]const u8, out_component: ?*Cid) callconv(.c) abi_result.c.ke_result {
    const w = walkOf(ctx) orelse return R.code(error.InvalidArgument);
    return vtFindComponent(&w.behaviour.owner.state.api, name, out_component);
}

fn actionNamed(s: *State, name: ?[*:0]const u8) ?i32 {
    const actions = s.actions orelse return null;
    const key = std.mem.span(name orelse return null);
    if (s.action_ids.get(key)) |id| return if (id < 0) null else id;
    const id = actions.get_action_id.?(actions, name);
    if (id < 0) log.warn("node types: no input action is named {s}", .{key});
    const owned = heap.gpa.dupe(u8, key) catch return if (id < 0) null else id;
    s.action_ids.put(heap.gpa, owned, id) catch heap.gpa.free(owned);
    return if (id < 0) null else id;
}

/// Slot `pressed_named`. Looks the action up by name once and keeps the id.
fn pressedNamed(ctx: ?*abi_framework.c.ke_node_ctx, name: ?[*:0]const u8) callconv(.c) bool {
    const w = walkOf(ctx) orelse return false;
    const s = w.behaviour.owner.state;
    const id = actionNamed(s, name) orelse return false;
    return s.actions.?.was_action_pressed.?(s.actions.?, id);
}

/// Slot `axis_named`. Looks the action up by name once and keeps the id.
fn axisNamed(ctx: ?*abi_framework.c.ke_node_ctx, name: ?[*:0]const u8) callconv(.c) f32 {
    const w = walkOf(ctx) orelse return 0;
    const s = w.behaviour.owner.state;
    const id = actionNamed(s, name) orelse return 0;
    return s.actions.?.get_axis1d.?(s.actions.?, id);
}

/// Slot `exit`. Forwards the request to the scheduler.
fn exit(ctx: ?*abi_framework.c.ke_node_ctx) callconv(.c) void {
    const w = walkOf(ctx) orelse return;
    const loop = w.behaviour.owner.state.loop;
    loop.request_exit.?(loop);
}

/// Slot `raise`. Records an entity carrying a copy of `data` as the event.
fn raise(ctx: ?*abi_framework.c.ke_node_ctx, event_cid: Cid, data: ?*const anyopaque, size: usize) callconv(.c) abi_result.c.ke_result {
    const w = walkOf(ctx) orelse return R.code(error.InvalidArgument);
    const s = w.behaviour.owner.state;
    const e = findEvent(s, event_cid) orelse {
        log.warn("node types: raising an event never registered ({d})", .{event_cid});
        return R.code(error.NotFound);
    };
    if (size != e.size or data == null) {
        log.warn("node types: event {s} is {d} bytes, raised with {d}", .{ e.name, e.size, size });
        return R.code(error.InvalidArgument);
    }
    const commands = w.api.commands;
    var entity: Entity = invalid;
    var rc = commands.?.spawn.?(commands, &entity);
    if (rc != R.ok) return rc;
    rc = commands.?.attach.?(commands, entity, e.cid, data, size);
    if (rc != R.ok) return rc;
    const stamp: EventStamp = .{ .sequence = s.loop.sequence.?(s.loop) };
    return commands.?.attach.?(commands, entity, s.stamp_cid, &stamp, @sizeOf(EventStamp));
}

fn viewOf(sys: ?*abi_schedule.c.ke_schedule_ctx, query: u32) []const abi_ecs.c.ke_ecs_segment {
    var count: usize = 0;
    const segs = sys.?.view.?(sys, query, &count) orelse return &.{};
    return segs[0..count];
}

/// The body of every behaviour system: builds the walk over the system's queries and hands it to
/// the behaviour once.
fn behaviourSystem(sys: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, dt: f32) callconv(.c) abi_result.c.ke_result {
    const b: *Behaviour = @ptrCast(@alignCast(user orelse return R.ok));
    var w: Walk = .{
        .api = .{
            .self = invalid,
            .dt = dt,
            .commands = sys.?.commands,
            .next = &next,
            .get = &get,
            .component = &component,
            .parent = &parent,
            .child = &child,
            .first_child = &firstChild,
            .next_sibling = &nextSibling,
            .ancestor = &ancestor,
            .axis = &axis,
            .pressed = &pressed,
            .spawn = &spawn,
            .change_scene = &changeScene,
            .destroy = &destroy,
            .raise = &raise,
            .exit = &exit,
            .find_type = &ctxFindType,
            .find_component = &ctxFindComponent,
            .pressed_named = &pressedNamed,
            .axis_named = &axisNamed,
        },
        .behaviour = b,
        .segs = &.{},
    };
    w.api.handle = &w;
    if (b.kind == .on) {
        w.api.event_type = b.event.?.cid;
        w.events = viewOf(sys, 0);
        w.segs = viewOf(sys, 1);
        while (w.ev_seg < w.events.len and w.events[w.ev_seg].count == 0) w.ev_seg += 1;
        if (w.ev_seg >= w.events.len or w.segs.len == 0) return R.ok;
    } else {
        w.segs = viewOf(sys, 0);
    }
    return b.run.?(&w.api, b.owner.user_data);
}

/// The PreUpdate system of an event type: records the destruction of every event of the type.
/// The body of an event's clearing system: despawns the events of its type that every schedule
/// reading the type has seen.
fn clearEvents(sys: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const e: *Event = @ptrCast(@alignCast(user orelse return R.ok));
    const commands = sys.?.commands;
    for (viewOf(sys, 0)) |seg| {
        const stamps: [*]const EventStamp = @ptrCast(@alignCast(seg.columns.?[1].?));
        for (seg.entities.?[0..seg.count], stamps[0..seg.count]) |entity, stamp| {
            if (!seenByEveryReader(e.owner, e.cid, stamp.sequence)) continue;
            const rc = commands.?.despawn.?(commands, entity);
            if (rc != R.ok) return rc;
        }
    }
    return R.ok;
}

/// Whether every schedule of the node types that reads `cid` completed a run numbered `stamp` or
/// later, each schedule being the user its executable was added to the scheduler with.
fn seenByEveryReader(s: *State, cid: Cid, stamp: u64) bool {
    if (!s.attached) return true;
    for ([_]*abi_schedule.c.ke_schedule{ s.first, s.fixed, s.main, s.post }) |schedule| {
        if (!schedule.reads.?(schedule, cid)) continue;
        if (!s.loop.completed_since.?(s.loop, schedule, stamp)) return false;
    }
    return true;
}

fn scheduleOf(s: *State, kind: Kind) *abi_schedule.c.ke_schedule {
    return switch (kind) {
        .ready, .exit => s.first,
        .fixed_update => s.fixed,
        .update => s.main,
        .on => s.post,
    };
}

fn setOf(s: *State, kind: Kind) *const [1]abi_schedule.c.ke_schedule_set_id {
    return switch (kind) {
        .ready, .exit => &s.pre_update,
        .update => &s.update,
        .fixed_update => &s.fixed_update,
        .on => &s.post_update,
    };
}

fn freeBehaviour(b: *Behaviour) void {
    heap.gpa.free(b.name);
    heap.gpa.free(b.terms);
    heap.gpa.destroy(b);
}

fn unregisterBehaviour(s: *State, b: *Behaviour) void {
    if (!b.registered) return;
    const schedule = scheduleOf(s, b.kind);
    _ = schedule.unregister_system.?(schedule, b.system);
    b.registered = false;
}

fn freeType(s: *State, t: *Type) void {
    for (t.behaviours.items) |b| {
        unregisterBehaviour(s, b);
        freeBehaviour(b);
    }
    t.behaviours.deinit(heap.gpa);
    for (t.prototypes) |p| heap.gpa.free(p);
    heap.gpa.free(t.prototypes);
    heap.gpa.free(t.sizes);
    heap.gpa.free(t.columns);
    heap.gpa.destroy(t);
}

fn addBehaviour(s: *State, t: *Type, kind: Kind, run: abi_framework.c.ke_node_behaviour_fn, event: ?*Event, type_name: []const u8) R.Error!void {
    const suffix = switch (kind) {
        .ready => "ready",
        .update => "update",
        .fixed_update => "fixed_update",
        .on => "on",
        .exit => "exit_tree",
    };
    const name = std.fmt.allocPrintSentinel(heap.gpa, "{s}.{s}{s}{s}", .{ type_name, suffix, if (event) |_| "." else "", if (event) |e| e.name else "" }, 0) catch return error.OutOfMemory;
    errdefer heap.gpa.free(name);
    const extra: usize = 2;
    const terms = heap.gpa.alloc(abi_ecs.c.ke_ecs_query_term, t.columns.len + extra) catch return error.OutOfMemory;
    errdefer heap.gpa.free(terms);
    terms[0] = .{ .component = t.tag, .access = abi_ecs.c.KE_ECS_ACCESS_READ };
    for (t.columns, 1..) |c, i| terms[i] = .{ .component = c, .access = abi_ecs.c.KE_ECS_ACCESS_WRITE };
    terms[t.columns.len + 1] = .{ .component = s.status_cid, .access = if (kind == .ready or kind == .exit) abi_ecs.c.KE_ECS_ACCESS_WRITE else abi_ecs.c.KE_ECS_ACCESS_READ };

    const b = heap.gpa.create(Behaviour) catch return error.OutOfMemory;
    errdefer heap.gpa.destroy(b);
    b.* = .{ .owner = t, .kind = kind, .run = run, .event = event, .name = name, .terms = terms };
    if (event) |e| {
        b.event_terms = .{.{ .component = e.cid, .access = abi_ecs.c.KE_ECS_ACCESS_READ }};
        b.queries = .{
            .{ .terms = &b.event_terms, .term_count = 1 },
            .{ .terms = terms.ptr, .term_count = @intCast(terms.len) },
        };
    } else {
        b.queries[0] = .{ .terms = terms.ptr, .term_count = @intCast(terms.len) };
    }
    t.behaviours.append(heap.gpa, b) catch return error.OutOfMemory;
    errdefer _ = t.behaviours.pop();
    if (s.attached) try registerBehaviour(s, b);
}

fn registerBehaviour(s: *State, b: *Behaviour) R.Error!void {
    var params = std.mem.zeroes(abi_schedule.c.ke_schedule_system_desc);
    params.name = b.name.ptr;
    params.sets = setOf(s, b.kind);
    params.set_count = 1;
    params.user_data = b;
    params.execute = behaviourSystem;
    params.exclusive = true;
    params.query_count = if (b.event != null) 2 else 1;
    params.queries = &b.queries;
    const schedule = scheduleOf(s, b.kind);
    try R.check(schedule.register_system.?(schedule, &params, &b.system));
    b.registered = true;
}

fn prototypeOf(size: usize, initial: ?*const anyopaque, initial_size: usize, type_name: [*:0]const u8) R.Error![]align(16) u8 {
    if (if (initial == null) initial_size != 0 else initial_size != size) {
        log.warn("node types: type {s} gives an initial of {d} bytes to a component of {d}", .{ type_name, initial_size, size });
        return error.InvalidArgument;
    }
    const p = heap.gpa.alignedAlloc(u8, prototype_alignment, size) catch return error.OutOfMemory;
    if (initial) |bytes| @memcpy(p, @as([*]const u8, @ptrCast(bytes))[0..size]) else @memset(p, 0);
    return p;
}

fn registerType(s: *State, desc: *const abi_framework.c.ke_node_type_desc) R.Error!Cid {
    const name = desc.name orelse return error.InvalidArgument;
    if (desc.fields_size == 0 and (desc.field_count != 0 or desc.initial != null)) {
        log.warn("node types: type {s} has a field table or initial bytes but no fields", .{name});
        return error.InvalidArgument;
    }
    const events: []const Cid = if (desc.event_count == 0) &.{} else (desc.events orelse return error.InvalidArgument)[0..desc.event_count];
    if (events.len > 0 and desc.on == null) {
        log.warn("node types: type {s} names events but no on behaviour", .{name});
        return error.InvalidArgument;
    }
    for (events) |event| {
        if (findEvent(s, event) == null) {
            log.warn("node types: type {s} handles an event never registered ({d})", .{ name, event });
            return error.NotFound;
        }
    }

    const own: usize = if (desc.fields_size != 0) 1 else 0;
    const count = own + desc.with_count;
    const t = heap.gpa.create(Type) catch return error.OutOfMemory;
    t.* = .{ .state = s, .tag = 0, .has_fields = own == 1, .columns = &.{}, .sizes = &.{}, .prototypes = &.{}, .user_data = desc.user_data };
    errdefer freeType(s, t);
    t.columns = heap.gpa.alloc(Cid, count) catch return error.OutOfMemory;
    t.sizes = heap.gpa.alloc(usize, count) catch return error.OutOfMemory;
    t.prototypes = heap.gpa.alloc([]align(16) u8, count) catch return error.OutOfMemory;
    for (t.prototypes) |*p| p.* = &.{};

    for (0..desc.with_count) |i| {
        const with_name = desc.with.?[i].name orelse return error.InvalidArgument;
        var meta = std.mem.zeroes(abi_ecs.c.ke_component_meta);
        if (!s.ecs.component_lookup.?(s.ecs, with_name, &meta)) {
            log.warn("node types: type {s} carries {s}, which is not registered", .{ name, with_name });
            return error.NotFound;
        }
        t.columns[own + i] = meta.cid;
        t.sizes[own + i] = meta.size;
        t.prototypes[own + i] = try prototypeOf(meta.size, desc.with.?[i].initial, desc.with.?[i].initial_size, name);
    }
    const tag_name = std.fmt.allocPrintSentinel(heap.gpa, "node.{s}", .{name}, 0) catch return error.OutOfMemory;
    defer heap.gpa.free(tag_name);
    const tag: abi_ecs.c.ke_component_desc = .{ .name = tag_name.ptr, .size = 0, .alignment = 0 };
    try R.check(s.ecs.component_register.?(s.ecs, &tag, &t.tag));
    if (desc.fields_size != 0) {
        const fields: abi_ecs.c.ke_component_desc = .{ .name = name, .size = desc.fields_size, .alignment = desc.fields_alignment, .fields = desc.fields, .field_count = desc.field_count };
        try R.check(s.ecs.component_register.?(s.ecs, &fields, &t.columns[0]));
        t.sizes[0] = desc.fields_size;
        t.prototypes[0] = try prototypeOf(desc.fields_size, desc.initial, desc.initial_size, name);
    }

    const type_name = std.mem.span(name);
    if (desc.ready != null) try addBehaviour(s, t, .ready, desc.ready, null, type_name);
    if (desc.update != null) try addBehaviour(s, t, .update, desc.update, null, type_name);
    if (desc.fixed_update != null) try addBehaviour(s, t, .fixed_update, desc.fixed_update, null, type_name);
    if (desc.exit_tree != null) try addBehaviour(s, t, .exit, desc.exit_tree, null, type_name);
    t.has_exit = desc.exit_tree != null;
    for (events) |event| try addBehaviour(s, t, .on, desc.on, findEvent(s, event), type_name);

    s.types.append(heap.gpa, t) catch return error.OutOfMemory;
    return t.tag;
}

/// Slot `register_type`.
fn vtRegisterType(self: ?*abi_framework.c.ke_node_types, desc_in: ?*const abi_framework.c.ke_node_type_desc, out_type: ?*Cid) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    const desc = desc_in orelse return R.code(error.InvalidArgument);
    const out = out_type orelse return R.code(error.InvalidArgument);
    out.* = registerType(s, desc) catch |err| return R.code(err);
    return R.ok;
}

fn registerEvent(s: *State, params: *const abi_ecs.c.ke_component_desc) R.Error!Cid {
    const name = params.name orelse return error.InvalidArgument;
    const e = heap.gpa.create(Event) catch return error.OutOfMemory;
    errdefer heap.gpa.destroy(e);
    e.* = .{ .owner = s, .cid = 0, .size = params.size, .name = heap.gpa.dupeZ(u8, std.mem.span(name)) catch return error.OutOfMemory };
    errdefer heap.gpa.free(e.name);
    try R.check(s.ecs.component_register.?(s.ecs, params, &e.cid));
    e.terms = .{ .{ .component = e.cid, .access = abi_ecs.c.KE_ECS_ACCESS_WRITE }, .{ .component = s.stamp_cid, .access = abi_ecs.c.KE_ECS_ACCESS_READ } };
    e.queries = .{.{ .terms = &e.terms, .term_count = 2 }};
    s.events.append(heap.gpa, e) catch return error.OutOfMemory;
    errdefer _ = s.events.pop();
    if (s.attached) try registerClear(s, e);
    return e.cid;
}

fn registerClear(s: *State, e: *Event) R.Error!void {
    const system_name = std.fmt.allocPrintSentinel(heap.gpa, "{s}.clear", .{e.name}, 0) catch return error.OutOfMemory;
    defer heap.gpa.free(system_name);
    var p = std.mem.zeroes(abi_schedule.c.ke_schedule_system_desc);
    p.name = system_name.ptr;
    p.sets = &s.pre_update;
    p.set_count = 1;
    p.user_data = e;
    p.execute = clearEvents;
    p.queries = &e.queries;
    p.query_count = 1;
    try R.check(s.first.register_system.?(s.first, &p, &e.system));
    e.registered = true;
}

/// Slot `register_event`.
fn vtRegisterEvent(self: ?*abi_framework.c.ke_node_types, params_in: ?*const abi_ecs.c.ke_component_desc, out_event: ?*Cid) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    const params = params_in orelse return R.code(error.InvalidArgument);
    const out = out_event orelse return R.code(error.InvalidArgument);
    out.* = registerEvent(s, params) catch |err| return R.code(err);
    return R.ok;
}

/// The destroy of the handle. Unregisters every system and frees the types, the events and the
/// `State`.
/// Slot `spawn`. Records the node through the scene tree, then its type's components, each a copy
/// of its prototype, and a status not yet readied.
fn vtSpawn(self: ?*abi_framework.c.ke_node_types, commands_in: ?*abi_ecs.c.ke_ecs_commands, type_cid: Cid, name: ?[*:0]const u8, under: Entity, components: ?[*]const abi_framework.c.ke_node_component, count: u32, out_node: ?*Entity) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    const commands = commands_in orelse return R.code(error.InvalidArgument);
    const out = out_node orelse return R.code(error.InvalidArgument);
    return spawnNode(s, commands, type_cid, name, under, components, count, out);
}

/// Slot `find_type`. Looks up the tag the type was registered under in the ecs.
fn vtFindType(self: ?*abi_framework.c.ke_node_types, name_in: ?[*:0]const u8, out_type: ?*Cid) callconv(.c) abi_result.c.ke_result {
    const out = out_type orelse return R.code(error.InvalidArgument);
    out.* = abi_ecs.c.KE_COMPONENT_INVALID;
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    const name = name_in orelse return R.code(error.InvalidArgument);
    const tag_name = std.fmt.allocPrintSentinel(heap.gpa, "node.{s}", .{name}, 0) catch return R.code(error.OutOfMemory);
    defer heap.gpa.free(tag_name);
    var meta = std.mem.zeroes(abi_ecs.c.ke_component_meta);
    if (!s.ecs.component_lookup.?(s.ecs, tag_name.ptr, &meta) or findType(s, meta.cid) == null) {
        log.warn("node types: no type is registered as {s}", .{name});
        return R.code(error.NotFound);
    }
    out.* = meta.cid;
    return R.ok;
}

/// Slot `find_component`. Asks the ecs for the component registered under the name.
fn vtFindComponent(self: ?*abi_framework.c.ke_node_types, name_in: ?[*:0]const u8, out_component: ?*Cid) callconv(.c) abi_result.c.ke_result {
    const out = out_component orelse return R.code(error.InvalidArgument);
    out.* = abi_ecs.c.KE_COMPONENT_INVALID;
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    const name = name_in orelse return R.code(error.InvalidArgument);
    var meta = std.mem.zeroes(abi_ecs.c.ke_component_meta);
    if (!s.ecs.component_lookup.?(s.ecs, name, &meta)) {
        log.warn("node types: no component is registered as {s}", .{name});
        return R.code(error.NotFound);
    }
    out.* = meta.cid;
    return R.ok;
}

/// Slot `initial`. The prototype the type copies into each node it spawns.
fn vtInitial(self: ?*abi_framework.c.ke_node_types, type_cid: Cid, carried: Cid) callconv(.c) ?*const anyopaque {
    const s = stateOf(self) orelse return null;
    const t = findType(s, type_cid) orelse return null;
    for (t.columns, t.prototypes) |c, proto| {
        if (c == carried) return proto.ptr;
    }
    return null;
}

/// Slot `carries`.
fn vtCarries(self: ?*abi_framework.c.ke_node_types, type_cid: Cid, cid: Cid) callconv(.c) bool {
    const s = stateOf(self) orelse return false;
    const t = findType(s, type_cid) orelse return false;
    return std.mem.indexOfScalar(Cid, t.columns, cid) != null;
}

fn vtDestroy(self_in: ?*abi_framework.c.ke_node_types) callconv(.c) void {
    const s = stateOf(self_in) orelse return;
    detachFrom(s);
    for (s.types.items) |t| freeType(s, t);
    s.types.deinit(heap.gpa);
    for (s.events.items) |e| {
        heap.gpa.free(e.name);
        heap.gpa.destroy(e);
    }
    s.events.deinit(heap.gpa);
    var keys = s.action_ids.keyIterator();
    while (keys.next()) |k| heap.gpa.free(k.*);
    s.action_ids.deinit(heap.gpa);
    heap.gpa.destroy(s);
}

fn detachFrom(s: *State) void {
    if (!s.attached) return;
    for (s.types.items) |t| for (t.behaviours.items) |b| unregisterBehaviour(s, b);
    for (s.events.items) |e| if (e.registered) {
        _ = s.first.unregister_system.?(s.first, e.system);
        e.registered = false;
    };
    _ = s.post.unregister_system.?(s.post, s.reap);
    s.attached = false;
}

const Hooks = struct {
    first: *abi_schedule.c.ke_schedule,
    first_set: abi_schedule.c.ke_schedule_set_id,
    fixed: *abi_schedule.c.ke_schedule,
    fixed_set: abi_schedule.c.ke_schedule_set_id,
    main: *abi_schedule.c.ke_schedule,
    main_set: abi_schedule.c.ke_schedule_set_id,
    post: *abi_schedule.c.ke_schedule,
    post_set: abi_schedule.c.ke_schedule_set_id,
};

/// Registers the reaping system, then the systems of every event and type registered so far; a
/// failure leaves none registered.
fn attachTo(s: *State, hooks: Hooks) R.Error!void {
    if (s.attached) return error.NotSupported;
    s.first = hooks.first;
    s.fixed = hooks.fixed;
    s.main = hooks.main;
    s.post = hooks.post;
    s.pre_update = .{hooks.first_set};
    s.fixed_update = .{hooks.fixed_set};
    s.update = .{hooks.main_set};
    s.post_update = .{hooks.post_set};
    var reap = std.mem.zeroes(abi_schedule.c.ke_schedule_system_desc);
    reap.name = "nodes.reap";
    reap.sets = &s.post_update;
    reap.set_count = 1;
    reap.user_data = s;
    reap.execute = reapLeaving;
    reap.queries = &s.reap_queries;
    reap.query_count = 1;
    reap.exclusive = true;
    try R.check(s.post.register_system.?(s.post, &reap, &s.reap));
    s.attached = true;
    errdefer detachFrom(s);
    for (s.events.items) |e| try registerClear(s, e);
    for (s.types.items) |t| for (t.behaviours.items) |b| try registerBehaviour(s, b);
}

/// The owner's destroy: unregisters every system the node types registered; the types, the events
/// and the state stay with the node types.
fn moduleDestroy(ref: ?*anyopaque) callconv(.c) void {
    detachFrom(@ptrCast(@alignCast(ref orelse return)));
}

/// Factory of the module that registers the systems of node types this library created, in the set
/// of each hook. The module lives in the node types' state and must be destroyed before them; a
/// second one over the same node types while the first lives is not supported.
export fn ke_node_types_systems_create(
    types_in: ?*abi_framework.c.ke_node_types,
    pre_update: ?*abi_schedule.c.ke_schedule,
    pre_update_set: abi_schedule.c.ke_schedule_set_id,
    fixed_update: ?*abi_schedule.c.ke_schedule,
    fixed_update_set: abi_schedule.c.ke_schedule_set_id,
    update: ?*abi_schedule.c.ke_schedule,
    update_set: abi_schedule.c.ke_schedule_set_id,
    post_update: ?*abi_schedule.c.ke_schedule,
    post_update_set: abi_schedule.c.ke_schedule_set_id,
    out_module: ?*abi_part.c.ke_owner,
) callconv(.c) abi_result.c.ke_result {
    const out = out_module orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_part.c.ke_owner);
    const types = types_in orelse return R.code(error.InvalidArgument);
    if (types.register_type != &vtRegisterType) {
        log.warn("node types module: the node types were not created by this library", .{});
        return R.code(error.InvalidArgument);
    }
    const s = stateOf(types) orelse return R.code(error.InvalidArgument);
    attachTo(s, .{
        .first = pre_update orelse return R.code(error.InvalidArgument),
        .first_set = pre_update_set,
        .fixed = fixed_update orelse return R.code(error.InvalidArgument),
        .fixed_set = fixed_update_set,
        .main = update orelse return R.code(error.InvalidArgument),
        .main_set = update_set,
        .post = post_update orelse return R.code(error.InvalidArgument),
        .post_set = post_update_set,
    }) catch |err| {
        log.warn("creating the node types systems failed: {t}", .{err});
        return R.code(err);
    };
    out.* = .{ .ref = s, .destroy = moduleDestroy };
    return R.ok;
}

fn create(loop: *abi_scheduler.c.ke_scheduler, ecs: *abi_ecs.c.ke_ecs, tree: *abi_scene_tree.c.ke_scene_tree, actions: ?*abi_input_actions.c.ke_input_actions) R.Error!abi_framework.c.ke_node_types_handle {
    var name_meta = std.mem.zeroes(abi_ecs.c.ke_component_meta);
    if (!ecs.component_lookup.?(ecs, abi_framework_components.c.KE_COMPONENT_NAME_NAME, &name_meta)) {
        log.warn("node types: the scene tree components are not registered on this ecs", .{});
        return error.NotFound;
    }
    var status_cid: Cid = 0;
    var status_meta = std.mem.zeroes(abi_ecs.c.ke_component_meta);
    if (ecs.component_lookup.?(ecs, status_name, &status_meta)) {
        status_cid = status_meta.cid;
    } else {
        const params: abi_ecs.c.ke_component_desc = .{ .name = status_name, .size = @sizeOf(NodeStatus), .alignment = @alignOf(NodeStatus) };
        try R.check(ecs.component_register.?(ecs, &params, &status_cid));
    }
    var stamp_cid: Cid = 0;
    var stamp_meta = std.mem.zeroes(abi_ecs.c.ke_component_meta);
    if (ecs.component_lookup.?(ecs, stamp_name, &stamp_meta)) {
        stamp_cid = stamp_meta.cid;
    } else {
        const params: abi_ecs.c.ke_component_desc = .{ .name = stamp_name, .size = @sizeOf(EventStamp), .alignment = @alignOf(EventStamp) };
        try R.check(ecs.component_register.?(ecs, &params, &stamp_cid));
    }

    const s = heap.gpa.create(State) catch return error.OutOfMemory;
    s.* = .{
        .api = .{ .register_type = &vtRegisterType, .register_event = &vtRegisterEvent, .spawn = &vtSpawn, .carries = &vtCarries, .find_type = &vtFindType, .find_component = &vtFindComponent, .initial = &vtInitial },
        .loop = loop,
        .ecs = ecs,
        .tree = tree,
        .actions = actions,
        .status_cid = status_cid,
        .stamp_cid = stamp_cid,
        .name_cid = name_meta.cid,
    };
    s.api.handle = s;
    errdefer vtDestroy(&s.api);
    s.reap_terms = .{.{ .component = status_cid, .access = abi_ecs.c.KE_ECS_ACCESS_WRITE }};
    s.reap_queries = .{.{ .terms = &s.reap_terms, .term_count = 1 }};
    var base = std.mem.zeroes(abi_framework.c.ke_node_type_desc);
    base.name = base_type_name;
    _ = try registerType(s, &base);
    return .{ .ref = &s.api, .destroy = vtDestroy };
}

/// Factory. A null scheduler, ecs, scene tree or out handle fails as an invalid argument; an ecs
/// without the scene tree components fails as not found; a refused registration fails with the
/// ecs's code. Each leaves the handle zeroed.
export fn ke_node_types_create(
    loop_in: ?*abi_scheduler.c.ke_scheduler,
    ecs_in: ?*abi_ecs.c.ke_ecs,
    tree_in: ?*abi_scene_tree.c.ke_scene_tree,
    actions: ?*abi_input_actions.c.ke_input_actions,
    out_types: ?*abi_framework.c.ke_node_types_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_types orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_framework.c.ke_node_types_handle);
    const loop = loop_in orelse return R.code(error.InvalidArgument);
    const ecs = ecs_in orelse return R.code(error.InvalidArgument);
    const tree = tree_in orelse return R.code(error.InvalidArgument);
    out.* = create(loop, ecs, tree, actions) catch |err| return R.code(err);
    return R.ok;
}

var engine_node_types_owner: u8 = 0;

/// The owner's destroy of the engine node types part: releases nothing, the types stay with the
/// node types they were registered in.
fn engineNodeTypesDestroy(_: ?*anyopaque) callconv(.c) void {}

/// Factory of the engine node types part: registers every type of `ke_engine_node_types` through
/// `types`. A null argument fails as an invalid argument, and a refused type with the node types'
/// code, the types registered before it staying.
fn createEngineNodeTypes(types_in: ?*abi_framework.c.ke_node_types, out_owner: ?*abi_part.c.ke_owner) callconv(.c) abi_result.c.ke_result {
    const out = out_owner orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_part.c.ke_owner);
    const types = types_in orelse return R.code(error.InvalidArgument);
    for (&abi_engine_node_types.c.ke_engine_node_types) |*desc| {
        var cid: Cid = 0;
        const made = types.register_type.?(types, @ptrCast(desc), &cid);
        if (made != R.ok) {
            log.warn("engine node types: registering {s} failed", .{std.mem.span(desc.name.?)});
            return made;
        }
    }
    out.* = .{ .ref = &engine_node_types_owner, .destroy = engineNodeTypesDestroy };
    return R.ok;
}

pub const parts = [_]abi_part.c.ke_part{
    part.of(ke_node_types_create, .{ .name = "node_types", .slots = &.{ "scheduler", "ecs", "scene_tree", "input_actions" }, .optional = &.{"input_actions"} }),
    part.of(ke_node_types_systems_create, .{ .name = "node_types_systems", .slots = &.{"types"}, .hooks = &.{
        "pre_update",
        "fixed_update",
        "update",
        "post_update",
    } }),
    part.of(createEngineNodeTypes, .{ .name = "engine_node_types", .slots = &.{"node_types"} }),
};

const testing = std.testing;
const zsub = @import("zsub");

const Paddle = extern struct { speed: f32, visits: u32 };
const Goal = extern struct { left: u8 };
const transform2d_cid: Cid = 50;
const name_cid: Cid = 40;

const test_sets = .{ .pre_update = 11, .update = 12, .fixed_update = 13, .post_update = 14 };

fn createAttached(f: *Fixture, actions: ?*abi_input_actions.c.ke_input_actions, out: *abi_framework.c.ke_node_types_handle) !void {
    try R.check(ke_node_types_create(f.loop.api(), f.ecs.api(), f.tree.api(), actions, out));
    var module: abi_part.c.ke_owner = undefined;
    const rt = f.rt.api();
    try R.check(ke_node_types_systems_create(out.ref, rt, test_sets.pre_update, rt, test_sets.fixed_update, rt, test_sets.update, rt, test_sets.post_update, &module));
}

var registered: [8]abi_schedule.c.ke_schedule_system_desc = undefined;
var registered_count: usize = 0;
var reap_params: abi_schedule.c.ke_schedule_system_desc = undefined;

fn recordSystem(args: zsub.For(abi_schedule.c.ke_schedule).Args(.register_system)) abi_result.c.ke_result {
    registered[registered_count] = args[1].?.*;
    registered_count += 1;
    args[2].?.* = registered_count;
    return R.ok;
}

var next_cid: Cid = 100;

var tag_names: [16][32]u8 = undefined;
var tag_cids: [16]Cid = undefined;
var tag_count: usize = 0;

fn registerComponent(args: zsub.For(abi_ecs.c.ke_ecs).Args(.component_register)) abi_result.c.ke_result {
    args[2].?.* = next_cid;
    const name = std.mem.span(args[1].?.name.?);
    if (tag_count < tag_names.len and name.len < tag_names[0].len) {
        @memset(&tag_names[tag_count], 0);
        @memcpy(tag_names[tag_count][0..name.len], name);
        tag_cids[tag_count] = next_cid;
        tag_count += 1;
    }
    next_cid += 1;
    return R.ok;
}

fn lookupComponent(args: zsub.For(abi_ecs.c.ke_ecs).Args(.component_lookup)) bool {
    const name = std.mem.span(args[1].?);
    const meta = args[2].?;
    meta.* = std.mem.zeroes(abi_ecs.c.ke_component_meta);
    if (std.mem.eql(u8, name, "name")) {
        meta.cid = name_cid;
    } else if (std.mem.eql(u8, name, "transform2d")) {
        meta.cid = transform2d_cid;
        meta.size = 8;
    } else {
        for (tag_names[0..tag_count], tag_cids[0..tag_count]) |*n, cid| {
            if (std.mem.eql(u8, std.mem.sliceTo(n, 0), name)) {
                meta.cid = cid;
                return true;
            }
        }
        return false;
    }
    return true;
}

const Fixture = struct {
    ecs: zsub.For(abi_ecs.c.ke_ecs) = undefined,
    rt: zsub.For(abi_schedule.c.ke_schedule) = undefined,
    loop: zsub.For(abi_scheduler.c.ke_scheduler) = undefined,
    tree: zsub.For(abi_scene_tree.c.ke_scene_tree) = undefined,
    types: abi_framework.c.ke_node_types_handle = undefined,

    fn init(f: *Fixture) !void {
        registered_count = 0;
        tag_count = 0;
        try f.ecs.init();
        try f.rt.init();
        try f.loop.init();
        try f.tree.init();
        _ = f.ecs.when(.component_lookup).does(lookupComponent);
        _ = f.ecs.when(.component_register).does(registerComponent);
        _ = f.rt.when(.register_system).does(recordSystem);
        try createAttached(f, null, &f.types);
        reap_params = registered[0];
        registered_count = 0;
    }

    fn deinit(f: *Fixture) void {
        f.types.destroy.?(f.types.ref);
        f.tree.deinit();
        f.loop.deinit();
        f.rt.deinit();
        f.ecs.deinit();
    }
};

const with_transform = [_]abi_framework.c.ke_node_with{.{ .name = "transform2d", .initial = null }};

fn paddleDesc() abi_framework.c.ke_node_type_desc {
    var d = std.mem.zeroes(abi_framework.c.ke_node_type_desc);
    d.name = "paddle";
    d.fields_size = @sizeOf(Paddle);
    d.fields_alignment = @alignOf(Paddle);
    d.with = &with_transform;
    d.with_count = 1;
    return d;
}

const Rows = struct {
    entities: [3]Entity = .{ 7, 8, 9 },
    paddles: [3]Paddle = .{ .{ .speed = 1, .visits = 0 }, .{ .speed = 2, .visits = 0 }, .{ .speed = 3, .visits = 0 } },
    transforms: [3][2]f32 = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
    status: [3]NodeStatus = .{ .{ .readied = 0 }, .{ .readied = 1 }, .{ .readied = 0 } },
    goals: [2]Goal = .{ .{ .left = 1 }, .{ .left = 0 } },
    goal_entities: [2]Entity = .{ 20, 21 },
    columns: [4]?*anyopaque = undefined,
    goal_columns: [1]?*anyopaque = undefined,
    segs: [2]abi_ecs.c.ke_ecs_segment = undefined,
    goal_segs: [1]abi_ecs.c.ke_ecs_segment = undefined,
    sys: abi_schedule.c.ke_schedule_ctx = undefined,
    with_events: bool = false,

    fn build(r: *Rows) void {
        r.columns = .{ null, &r.paddles, &r.transforms, &r.status };
        r.goal_columns = .{&r.goals};
        r.segs = .{
            .{ .entities = &r.entities, .count = 2, .columns = &r.columns, .column_count = 4 },
            .{ .entities = r.entities[2..].ptr, .count = 1, .columns = undefined, .column_count = 4 },
        };
        r.goal_segs = .{.{ .entities = &r.goal_entities, .count = 2, .columns = &r.goal_columns, .column_count = 1 }};
        r.sys = .{ .handle = r, .view = &view };
    }

    var second_columns: [4]?*anyopaque = undefined;

    fn view(sys: ?*abi_schedule.c.ke_schedule_ctx, query: u32, out_count: ?*usize) callconv(.c) ?[*]const abi_ecs.c.ke_ecs_segment {
        const r: *Rows = @ptrCast(@alignCast(sys.?.handle));
        second_columns = .{ null, @ptrCast(&r.paddles[2]), @ptrCast(&r.transforms[2]), @ptrCast(&r.status[2]) };
        r.segs[1].columns = &second_columns;
        if (r.with_events and query == 0) {
            out_count.?.* = 1;
            return &r.goal_segs;
        }
        out_count.?.* = 2;
        return &r.segs;
    }
};

fn runSystem(params: abi_schedule.c.ke_schedule_system_desc, rows: *Rows) !void {
    try R.check(params.execute.?(&rows.sys, params.user_data, 0.5));
}

fn countVisits(ctx: ?*abi_framework.c.ke_node_ctx, _: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    KE_FOR_EACH_NODE: while (ctx.?.next.?(ctx)) {
        const p: *Paddle = @ptrCast(@alignCast(ctx.?.fields.?));
        const t: *[2]f32 = @ptrCast(@alignCast(ctx.?.get.?(ctx, transform2d_cid).?));
        p.visits += 1;
        t[1] = p.speed * ctx.?.dt;
        continue :KE_FOR_EACH_NODE;
    }
    return R.ok;
}

test "registering a node type registers one exclusive system per behaviour in its phase" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var d = paddleDesc();
    d.ready = countVisits;
    d.update = countVisits;
    d.fixed_update = countVisits;
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    try testing.expect(cid != 0);
    try testing.expectEqual(@as(usize, 3), registered_count);
    try testing.expectEqual(test_sets.pre_update, registered[0].sets.?[0]);
    try testing.expectEqual(test_sets.update, registered[1].sets.?[0]);
    try testing.expectEqual(test_sets.fixed_update, registered[2].sets.?[0]);
    for (registered[0..3]) |p| try testing.expect(p.exclusive);
}

test "a type registered before the systems module gets its systems when the module is created, and destroying the module removes them while the type stays" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var detached: abi_framework.c.ke_node_types_handle = undefined;
    try R.check(ke_node_types_create(f.loop.api(), f.ecs.api(), f.tree.api(), null, &detached));
    defer detached.destroy.?(detached.ref);
    var d = paddleDesc();
    d.update = countVisits;
    var cid: Cid = 0;
    try R.check(detached.ref.?.register_type.?(detached.ref, &d, &cid));
    try testing.expectEqual(@as(usize, 0), registered_count);
    var module: abi_part.c.ke_owner = undefined;
    const rt = f.rt.api();
    try R.check(ke_node_types_systems_create(detached.ref, rt, 0, rt, 0, rt, test_sets.update, rt, 0, &module));
    try testing.expectEqual(@as(usize, 2), registered_count);
    try testing.expectEqual(test_sets.update, registered[1].sets.?[0]);
    module.destroy.?(module.ref);
    try f.rt.received(.unregister_system).times(2);
    var found: Cid = 0;
    try R.check(detached.ref.?.find_type.?(detached.ref, "paddle", &found));
}

test "the systems module refuses node types this library did not create" {
    var foreign = std.mem.zeroes(abi_framework.c.ke_node_types);
    var module: abi_part.c.ke_owner = undefined;
    var rt: zsub.For(abi_schedule.c.ke_schedule) = undefined;
    try rt.init();
    defer rt.deinit();
    try testing.expectEqual(R.code(error.InvalidArgument), ke_node_types_systems_create(&foreign, rt.api(), 0, rt.api(), 0, rt.api(), 0, rt.api(), 0, &module));
    try testing.expect(module.ref == null);
}

test "an update behaviour visits every node of its type with its fields and its with components" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var d = paddleDesc();
    d.update = countVisits;
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    var rows: Rows = .{};
    rows.build();
    try runSystem(registered[0], &rows);
    for (rows.paddles, rows.transforms) |p, t| {
        try testing.expectEqual(@as(u32, 1), p.visits);
        try testing.expectEqual(p.speed * 0.5, t[1]);
    }
}

var label_text: [8]u8 = .{0} ** 8;
const label_cid: Cid = 60;
const label_node: Entity = 30;

fn labelOf(args: zsub.For(abi_ecs.c.ke_ecs).Args(.component_get)) ?*anyopaque {
    return if (args[1] == label_node and args[2] == label_cid) &label_text else null;
}

fn writeLabel(ctx: ?*abi_framework.c.ke_node_ctx, _: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    while (ctx.?.next.?(ctx)) {
        const text: *[8]u8 = @ptrCast(ctx.?.component.?(ctx, label_node, label_cid) orelse return R.code(error.NotFound));
        text[0] += 1;
        if (ctx.?.component.?(ctx, ctx.?.self, label_cid) != null) return R.code(error.InvalidArgument);
    }
    return R.ok;
}

var launch_ref = std.mem.zeroes(abi_framework.c.ke_action_ref);
var launch_presses: u32 = 0;

fn actionIdOf(args: zsub.For(abi_input_actions.c.ke_input_actions).Args(.get_action_id)) i32 {
    return if (std.mem.eql(u8, std.mem.span(args[1].?), "Launch")) 0 else -1;
}

fn readLaunch(ctx: ?*abi_framework.c.ke_node_ctx, _: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    while (ctx.?.next.?(ctx)) {
        if (ctx.?.pressed.?(ctx, &launch_ref)) launch_presses += 1;
    }
    return R.ok;
}

test "an action reference is resolved by name on its first read, action 0 among them, and kept" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var actions: zsub.For(abi_input_actions.c.ke_input_actions) = undefined;
    try actions.init();
    defer actions.deinit();
    _ = actions.when(.get_action_id).does(actionIdOf);
    _ = actions.when(.was_action_pressed).returns(true);
    var with_actions: abi_framework.c.ke_node_types_handle = undefined;
    registered_count = 0;
    try createAttached(&f, actions.api(), &with_actions);
    defer with_actions.destroy.?(with_actions.ref);
    var d = paddleDesc();
    d.update = readLaunch;
    var cid: Cid = 0;
    try R.check(with_actions.ref.?.register_type.?(with_actions.ref, &d, &cid));
    launch_ref = std.mem.zeroes(abi_framework.c.ke_action_ref);
    @memcpy(launch_ref.name[0.."Launch".len], "Launch");
    launch_presses = 0;
    var rows: Rows = .{};
    rows.build();
    try runSystem(registered[registered_count - 1], &rows);
    try testing.expectEqual(@as(u32, 3), launch_presses);
    try testing.expect(launch_ref.resolved);
    try testing.expectEqual(@as(i32, 0), launch_ref.id);
    try actions.received(.get_action_id).times(1);
}

var named_presses: u32 = 0;

fn readLaunchByName(ctx: ?*abi_framework.c.ke_node_ctx, _: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    while (ctx.?.next.?(ctx)) {
        if (ctx.?.pressed_named.?(ctx, "Launch")) named_presses += 1;
    }
    return R.ok;
}

test "an action read by name is looked up once and kept" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var actions: zsub.For(abi_input_actions.c.ke_input_actions) = undefined;
    try actions.init();
    defer actions.deinit();
    _ = actions.when(.get_action_id).does(actionIdOf);
    _ = actions.when(.was_action_pressed).returns(true);
    var with_actions: abi_framework.c.ke_node_types_handle = undefined;
    registered_count = 0;
    try createAttached(&f, actions.api(), &with_actions);
    defer with_actions.destroy.?(with_actions.ref);
    var d = paddleDesc();
    d.update = readLaunchByName;
    var cid: Cid = 0;
    try R.check(with_actions.ref.?.register_type.?(with_actions.ref, &d, &cid));
    named_presses = 0;
    var rows: Rows = .{};
    rows.build();
    try runSystem(registered[registered_count - 1], &rows);
    try runSystem(registered[registered_count - 1], &rows);
    try testing.expectEqual(@as(u32, 6), named_presses);
    try actions.received(.get_action_id).times(1);
}

test "a node leaving the tree is skipped by update and visited once by exit" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var d = paddleDesc();
    d.update = countVisits;
    d.exit_tree = countVisits;
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    var rows: Rows = .{};
    rows.build();
    rows.status[1].exiting = 1;
    try runSystem(registered[0], &rows);
    try testing.expectEqual(@as(u32, 1), rows.paddles[0].visits);
    try testing.expectEqual(@as(u32, 0), rows.paddles[1].visits);
    try testing.expectEqual(test_sets.pre_update, registered[1].sets.?[0]);
    try runSystem(registered[1], &rows);
    try runSystem(registered[1], &rows);
    try testing.expectEqual(@as(u32, 1), rows.paddles[1].visits);
    try testing.expectEqual(@as(u8, 1), rows.status[1].exited);
}

var leaving_status = [_]NodeStatus{.{ .readied = 1, .exiting = 1, .has_exit = 1 }};
var leaving_entities = [_]Entity{12};
var leaving_columns: [1]?*anyopaque = undefined;
var leaving_segs: [1]abi_ecs.c.ke_ecs_segment = undefined;

fn leavingView(_: ?*abi_schedule.c.ke_schedule_ctx, _: u32, out_count: ?*usize) callconv(.c) ?[*]const abi_ecs.c.ke_ecs_segment {
    leaving_columns = .{&leaving_status};
    leaving_segs = .{.{ .entities = &leaving_entities, .count = 1, .columns = &leaving_columns, .column_count = 1 }};
    out_count.?.* = 1;
    return &leaving_segs;
}

fn leavingStatusOf(args: zsub.For(abi_ecs.c.ke_ecs).Args(.component_get)) ?*anyopaque {
    return if (args[1] == 12) &leaving_status[0] else null;
}

test "the reap removes a node leaving the tree only once its exit ran" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    _ = f.ecs.when(.component_get).does(leavingStatusOf);
    _ = f.tree.when(.parent).returns(invalid);
    _ = f.tree.when(.first_child).returns(invalid);
    _ = f.tree.when(.destroy_node_deferred).returns(R.ok);
    var sys: abi_schedule.c.ke_schedule_ctx = .{ .view = &leavingView };
    leaving_status[0].exited = 0;
    try R.check(reap_params.execute.?(&sys, reap_params.user_data, 0));
    try f.tree.received(.destroy_node_deferred).times(0);
    leaving_status[0].exited = 1;
    try R.check(reap_params.execute.?(&sys, reap_params.user_data, 0));
    try f.tree.received(.destroy_node_deferred).times(1);
}

fn askExit(ctx: ?*abi_framework.c.ke_node_ctx, _: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    ctx.?.exit.?(ctx);
    return R.ok;
}

test "exit forwards the request to the scheduler" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var d = paddleDesc();
    d.update = askExit;
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    var rows: Rows = .{};
    rows.build();
    try runSystem(registered[0], &rows);
    try f.loop.received(.request_exit).times(1);
}

test "component reaches another node's component and is null for one the node does not carry" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    _ = f.ecs.when(.component_get).does(labelOf);
    var d = paddleDesc();
    d.update = writeLabel;
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    var rows: Rows = .{};
    rows.build();
    label_text[0] = 0;
    try runSystem(registered[0], &rows);
    try testing.expectEqual(@as(u8, 3), label_text[0]);
}

test "ready visits only the nodes not yet readied and marks them" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var d = paddleDesc();
    d.ready = countVisits;
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    var rows: Rows = .{};
    rows.build();
    try runSystem(registered[0], &rows);
    try runSystem(registered[0], &rows);
    try testing.expectEqual(@as(u32, 1), rows.paddles[0].visits);
    try testing.expectEqual(@as(u32, 0), rows.paddles[1].visits);
    try testing.expectEqual(@as(u32, 1), rows.paddles[2].visits);
    for (rows.status) |st| try testing.expectEqual(@as(u8, 1), st.readied);
}

var lefts: u32 = 0;
var pairs: u32 = 0;

fn countGoals(ctx: ?*abi_framework.c.ke_node_ctx, _: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    while (ctx.?.next.?(ctx)) {
        const g: *const Goal = @ptrCast(ctx.?.event.?);
        if (ctx.?.event_type == 0) return R.code(error.General);
        pairs += 1;
        lefts += g.left;
    }
    return R.ok;
}

test "an on handler visits each pair of a node and an event raised this tick" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    const goal: abi_ecs.c.ke_component_desc = .{ .name = "pong.goal", .size = @sizeOf(Goal), .alignment = 1 };
    var goal_cid: Cid = 0;
    try R.check(f.types.ref.?.register_event.?(f.types.ref, &goal, &goal_cid));
    const events = [_]Cid{goal_cid};
    var d = paddleDesc();
    d.events = &events;
    d.event_count = 1;
    d.on = countGoals;
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    try testing.expectEqual(test_sets.pre_update, registered[0].sets.?[0]);
    try testing.expectEqual(test_sets.post_update, registered[1].sets.?[0]);
    var rows: Rows = .{ .with_events = true };
    rows.build();
    pairs = 0;
    lefts = 0;
    try runSystem(registered[1], &rows);
    try testing.expectEqual(@as(u32, 6), pairs);
    try testing.expectEqual(@as(u32, 3), lefts);
}

fn raiseGoal(ctx: ?*abi_framework.c.ke_node_ctx, user: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    const cid: *const Cid = @ptrCast(@alignCast(user.?));
    const g: Goal = .{ .left = 1 };
    if (ctx.?.raise.?(ctx, cid.*, &g, @sizeOf(Goal) + 1) != abi_result.c.KE_RESULT_INVALID_ARGUMENT) return R.code(error.General);
    return ctx.?.raise.?(ctx, cid.*, &g, @sizeOf(Goal));
}

test "raise records an entity carrying the event and refuses a size that is not the event's" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    const goal: abi_ecs.c.ke_component_desc = .{ .name = "pong.goal", .size = @sizeOf(Goal), .alignment = 1 };
    var goal_cid: Cid = 0;
    try R.check(f.types.ref.?.register_event.?(f.types.ref, &goal, &goal_cid));
    var d = paddleDesc();
    d.update = raiseGoal;
    d.user_data = &goal_cid;
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    var commands: zsub.For(abi_ecs.c.ke_ecs_commands) = undefined;
    try commands.init();
    defer commands.deinit();
    _ = commands.when(.spawn).writes(1, 30);
    var rows: Rows = .{};
    rows.build();
    rows.sys.commands = commands.api();
    try runSystem(registered[1], &rows);
    try commands.received(.spawn).times(1);
    try commands.received(.attach).where(zsub.argIs(1, @as(Entity, 30))).times(2);
    try f.loop.received(.sequence).times(1);
}

fn completedBelowFive(args: zsub.For(abi_scheduler.c.ke_scheduler).Args(.completed_since)) bool {
    return args[2] < 5;
}

const EventRows = struct {
    entities: [2]Entity = .{ 40, 41 },
    goals: [2]Goal = .{ .{ .left = 1 }, .{ .left = 0 } },
    stamps: [2]EventStamp = .{ .{ .sequence = 3 }, .{ .sequence = 6 } },
    columns: [2]?*anyopaque = undefined,
    segs: [1]abi_ecs.c.ke_ecs_segment = undefined,
    sys: abi_schedule.c.ke_schedule_ctx = undefined,

    fn build(r: *EventRows) void {
        r.columns = .{ &r.goals, &r.stamps };
        r.segs = .{.{ .entities = &r.entities, .count = 2, .columns = &r.columns, .column_count = 2 }};
        r.sys = .{ .handle = r, .view = &view };
    }

    fn view(sys: ?*abi_schedule.c.ke_schedule_ctx, _: u32, out_count: ?*usize) callconv(.c) ?[*]const abi_ecs.c.ke_ecs_segment {
        const r: *EventRows = @ptrCast(@alignCast(sys.?.handle));
        out_count.?.* = 1;
        return &r.segs;
    }
};

test "clearing despawns only the events every reading schedule has seen" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    _ = f.loop.when(.completed_since).does(&completedBelowFive);
    _ = f.rt.when(.reads).returns(true);
    const goal: abi_ecs.c.ke_component_desc = .{ .name = "pong.goal", .size = @sizeOf(Goal), .alignment = 1 };
    var goal_cid: Cid = 0;
    try R.check(f.types.ref.?.register_event.?(f.types.ref, &goal, &goal_cid));
    const clear = registered[0];
    try testing.expectEqual(2, clear.queries.?[0].term_count);
    var commands: zsub.For(abi_ecs.c.ke_ecs_commands) = undefined;
    try commands.init();
    defer commands.deinit();
    var rows: EventRows = .{};
    rows.build();
    rows.sys.commands = commands.api();
    try R.check(clear.execute.?(&rows.sys, clear.user_data, 0));
    try commands.received(.despawn).times(1);
    try commands.received(.despawn).where(zsub.argIs(1, @as(Entity, 40))).times(1);
}

fn spawnPaddle(ctx: ?*abi_framework.c.ke_node_ctx, user: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    const cid: *const Cid = @ptrCast(@alignCast(user.?));
    var node: Entity = invalid;
    return ctx.?.spawn.?(ctx, cid.*, "Paddle", invalid, null, 0, &node);
}

var found_ancestor: Entity = 0;
const held_cid: Cid = 77;
var held_bytes: u32 = 1;

fn parentOf(args: zsub.For(abi_scene_tree.c.ke_scene_tree).Args(.parent)) Entity {
    return switch (args[1]) {
        7 => 31,
        31 => 40,
        else => invalid,
    };
}

fn holdsAt40(args: zsub.For(abi_ecs.c.ke_ecs).Args(.component_get)) ?*anyopaque {
    return if (args[1] == 40 and args[2] == held_cid) &held_bytes else null;
}

fn findHolder(ctx: ?*abi_framework.c.ke_node_ctx, _: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    if (ctx.?.next.?(ctx)) found_ancestor = ctx.?.ancestor.?(ctx, ctx.?.self, held_cid);
    return R.ok;
}

test "ancestor answers the nearest ancestor holding a component, past one that does not" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var cid: Cid = 0;
    var d = paddleDesc();
    d.update = findHolder;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    _ = f.tree.when(.parent).does(parentOf);
    _ = f.ecs.when(.component_get).does(holdsAt40);
    var rows: Rows = .{};
    rows.build();
    try runSystem(registered[0], &rows);
    try testing.expectEqual(@as(Entity, 40), found_ancestor);
}

test "spawn records a node through the scene tree with each component of its type and its status" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var cid: Cid = 0;
    var d = paddleDesc();
    d.update = spawnPaddle;
    d.user_data = &cid;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    _ = f.tree.when(.create_node_deferred).writes(4, 31);
    var commands: zsub.For(abi_ecs.c.ke_ecs_commands) = undefined;
    try commands.init();
    defer commands.deinit();
    var rows: Rows = .{};
    rows.build();
    rows.sys.commands = commands.api();
    try runSystem(registered[0], &rows);
    try f.tree.received(.create_node_deferred).times(1);
    try commands.received(.attach).where(zsub.argIs(1, @as(Entity, 31))).times(4);
}

test "spawn outside a behaviour records into the given commands and refuses a type never registered" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var cid: Cid = 0;
    const d = paddleDesc();
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    _ = f.tree.when(.create_node_deferred).writes(4, 32);
    var commands: zsub.For(abi_ecs.c.ke_ecs_commands) = undefined;
    try commands.init();
    defer commands.deinit();
    var node: Entity = invalid;
    try R.check(f.types.ref.?.spawn.?(f.types.ref, commands.api(), cid, "Paddle", invalid, null, 0, &node));
    try testing.expectEqual(@as(Entity, 32), node);
    try commands.received(.attach).where(zsub.argIs(1, @as(Entity, 32))).times(4);
    try testing.expectEqual(R.code(error.NotFound), f.types.ref.?.spawn.?(f.types.ref, commands.api(), cid + 99, "X", invalid, null, 0, &node));
}

fn countBare(ctx: ?*abi_framework.c.ke_node_ctx, user: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    const seen: *u32 = @ptrCast(@alignCast(user.?));
    while (ctx.?.next.?(ctx)) {
        if (ctx.?.fields != null or ctx.?.get.?(ctx, transform2d_cid) == null) return R.code(error.InvalidArgument);
        seen.* += 1;
    }
    return R.ok;
}

test "a node type without fields carries its tag and its with components, and fields are null" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var seen: u32 = 0;
    var d = paddleDesc();
    d.fields_size = 0;
    d.update = countBare;
    d.user_data = &seen;
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    try testing.expectEqual(@as(u32, 3), registered[0].queries.?[0].term_count);
    var rows: Rows = .{};
    rows.build();
    rows.columns = .{ null, &rows.transforms, null, null };
    try R.check(registered[0].execute.?(&rows.sys, registered[0].user_data, 0.5));
    try testing.expect(seen > 0);
}

test "carries answers for the fields and the with components of a registered type only" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var cid: Cid = 0;
    const d = paddleDesc();
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    try testing.expect(f.types.ref.?.carries.?(f.types.ref, cid, transform2d_cid));
    try testing.expect(!f.types.ref.?.carries.?(f.types.ref, cid, name_cid));
    try testing.expect(!f.types.ref.?.carries.?(f.types.ref, cid + 99, transform2d_cid));
}

test "find_type answers the id of a type by its registered name, the base type among them" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var d = paddleDesc();
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    var found: Cid = 0;
    try R.check(f.types.ref.?.find_type.?(f.types.ref, "paddle", &found));
    try testing.expectEqual(cid, found);
    try R.check(f.types.ref.?.find_type.?(f.types.ref, "node", &found));
    try testing.expect(found != 0 and found != cid);
    try testing.expectError(error.NotFound, R.check(f.types.ref.?.find_type.?(f.types.ref, "transform2d", &found)));
    try testing.expectEqual(@as(Cid, 0), found);
}

test "find_component answers the id of a registered component and refuses an unknown name" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var found: Cid = 0;
    try R.check(f.types.ref.?.find_component.?(f.types.ref, "transform2d", &found));
    try testing.expectEqual(transform2d_cid, found);
    try testing.expectError(error.NotFound, R.check(f.types.ref.?.find_component.?(f.types.ref, "absent", &found)));
    try testing.expectEqual(@as(Cid, 0), found);
}

test "a nameless node type, or a field table without fields, is refused" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var cid: Cid = 0;
    var d = paddleDesc();
    d.name = null;
    try testing.expectEqual(abi_result.c.KE_RESULT_INVALID_ARGUMENT, f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    const table = [_]abi_ecs.c.ke_component_field{.{ .name = "speed", .offset = 0, .size = 4 }};
    d = paddleDesc();
    d.fields_size = 0;
    d.fields = &table;
    d.field_count = 1;
    try testing.expectEqual(abi_result.c.KE_RESULT_INVALID_ARGUMENT, f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    try testing.expectEqual(@as(usize, 0), registered_count);
}

test "a node type carrying an unregistered component is refused and registers nothing" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    const missing = [_]abi_framework.c.ke_node_with{.{ .name = "missing", .initial = null }};
    var d = paddleDesc();
    d.with = &missing;
    d.update = countVisits;
    var cid: Cid = 0;
    try testing.expectEqual(abi_result.c.KE_RESULT_NOT_FOUND, f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    try testing.expectEqual(@as(usize, 0), registered_count);
}

test "destroying the node types unregisters every system they registered" {
    var f: Fixture = .{};
    try f.init();
    const goal: abi_ecs.c.ke_component_desc = .{ .name = "pong.goal", .size = @sizeOf(Goal), .alignment = 1 };
    var goal_cid: Cid = 0;
    try R.check(f.types.ref.?.register_event.?(f.types.ref, &goal, &goal_cid));
    var d = paddleDesc();
    d.update = countVisits;
    d.fixed_update = countVisits;
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    f.types.destroy.?(f.types.ref);
    try f.rt.received(.unregister_system).times(4);
    f.tree.deinit();
    f.rt.deinit();
    f.ecs.deinit();
}

var attached_paddle: Paddle = .{ .speed = 0, .visits = 0 };
var paddle_column: Cid = 0;

fn capturePaddle(args: zsub.For(abi_ecs.c.ke_ecs_commands).Args(.attach)) abi_result.c.ke_result {
    if (args[2] == paddle_column) attached_paddle = @as(*const Paddle, @ptrCast(@alignCast(args[3].?))).*;
    return R.ok;
}

test "a type's initial bytes are the fields each spawned node starts with" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    const initial: Paddle = .{ .speed = 7, .visits = 2 };
    var d = paddleDesc();
    d.initial = &initial;
    d.initial_size = @sizeOf(Paddle);
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    paddle_column = findType(stateOf(f.types.ref).?, cid).?.columns[0];
    var commands: zsub.For(abi_ecs.c.ke_ecs_commands) = undefined;
    try commands.init();
    defer commands.deinit();
    _ = commands.when(.attach).does(capturePaddle);
    var node: Entity = invalid;
    try R.check(f.types.ref.?.spawn.?(f.types.ref, commands.api(), cid, "Paddle", invalid, null, 0, &node));
    try testing.expectEqual(initial, attached_paddle);
}

test "a component given to the spawn replaces its type's initial value, and one the type does not carry is refused" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    const initial: Paddle = .{ .speed = 7, .visits = 2 };
    var d = paddleDesc();
    d.initial = &initial;
    d.initial_size = @sizeOf(Paddle);
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    paddle_column = findType(stateOf(f.types.ref).?, cid).?.columns[0];
    var commands: zsub.For(abi_ecs.c.ke_ecs_commands) = undefined;
    try commands.init();
    defer commands.deinit();
    _ = commands.when(.attach).does(capturePaddle);
    const given: Paddle = .{ .speed = 3, .visits = 9 };
    const components = [_]abi_framework.c.ke_node_component{.{ .component = paddle_column, .data = &given, .size = @sizeOf(Paddle) }};
    var node: Entity = invalid;
    try R.check(f.types.ref.?.spawn.?(f.types.ref, commands.api(), cid, "Paddle", invalid, &components, 1, &node));
    try testing.expectEqual(given, attached_paddle);
    const foreign = [_]abi_framework.c.ke_node_component{.{ .component = 999, .data = &given, .size = @sizeOf(Paddle) }};
    try testing.expectEqual(R.code(error.InvalidArgument), f.types.ref.?.spawn.?(f.types.ref, commands.api(), cid, "Paddle", invalid, &foreign, 1, &node));
    const short = [_]abi_framework.c.ke_node_component{.{ .component = paddle_column, .data = &given, .size = @sizeOf(Paddle) - 1 }};
    try testing.expectEqual(R.code(error.InvalidArgument), f.types.ref.?.spawn.?(f.types.ref, commands.api(), cid, "Paddle", invalid, &short, 1, &node));
}

const paddle_table = [_]abi_ecs.c.ke_component_field{
    .{ .name = "speed", .type = abi_ecs_variant.c.KE_VARIANT_FLOAT, .offset = @offsetOf(Paddle, "speed"), .size = 4 },
    .{ .name = "visits", .type = abi_ecs_variant.c.KE_VARIANT_INT, .offset = @offsetOf(Paddle, "visits"), .size = 4 },
};
const slot_cid: Cid = 60;
const Slot = extern struct { path: [16]u8 };
const slot_table = [_]abi_ecs.c.ke_component_field{.{ .name = "path", .type = abi_ecs_variant.c.KE_VARIANT_STRING, .offset = 0, .size = 16 }};
var slot_at_40: Slot = .{ .path = .{0} ** 16 };

fn lookupWithTables(args: zsub.For(abi_ecs.c.ke_ecs).Args(.component_lookup)) bool {
    const name = std.mem.span(args[1].?);
    if (std.mem.eql(u8, name, scene_slot_name)) {
        args[2].?.* = .{ .cid = slot_cid, .size = @sizeOf(Slot), .fields = &slot_table, .field_count = slot_table.len };
        return true;
    }
    if (!lookupComponent(args)) return false;
    if (std.mem.eql(u8, name, "paddle")) {
        args[2].?.fields = &paddle_table;
        args[2].?.field_count = paddle_table.len;
    }
    return true;
}

fn writeByTable(args: zsub.For(abi_ecs.c.ke_ecs).Args(.component_field_write)) abi_result.c.ke_result {
    const at: [*]u8 = @as([*]u8, @ptrCast(args[1].?)) + args[2].?.offset;
    const v = args[3].?;
    switch (args[2].?.type) {
        abi_ecs_variant.c.KE_VARIANT_FLOAT => {
            if (v.type != abi_ecs_variant.c.KE_VARIANT_FLOAT) return R.code(error.InvalidArgument);
            @as(*align(1) f32, @ptrCast(at)).* = @floatCast(v.unnamed_0.f);
        },
        abi_ecs_variant.c.KE_VARIANT_STRING => {
            if (v.type != abi_ecs_variant.c.KE_VARIANT_STRING) return R.code(error.InvalidArgument);
            const text = std.mem.span(v.unnamed_0.s.?);
            @memset(at[0..args[2].?.size], 0);
            @memcpy(at[0..text.len], text);
        },
        else => return R.code(error.InvalidArgument),
    }
    return R.ok;
}

fn slotAt40(args: zsub.For(abi_ecs.c.ke_ecs).Args(.component_get)) ?*anyopaque {
    return if (args[1] == 40 and args[2] == slot_cid) &slot_at_40 else null;
}

var change_result: abi_result.c.ke_result = R.ok;

fn changeToMenu(ctx: ?*abi_framework.c.ke_node_ctx, _: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    if (ctx.?.next.?(ctx)) change_result = ctx.?.change_scene.?(ctx, "res://menu");
    return R.ok;
}

test "change_scene writes the path into the nearest ancestor's scene slot, and refuses one too long" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    _ = f.ecs.when(.component_lookup).does(lookupWithTables);
    _ = f.ecs.when(.component_field_write).does(writeByTable);
    _ = f.ecs.when(.component_get).does(slotAt40);
    _ = f.tree.when(.parent).does(parentOf);
    slot_at_40 = .{ .path = .{0} ** 16 };
    var d = paddleDesc();
    d.update = changeToMenu;
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    var rows: Rows = .{};
    rows.build();
    try runSystem(registered[0], &rows);
    try R.check(change_result);
    try testing.expectEqualStrings("res://menu", std.mem.sliceTo(&slot_at_40.path, 0));
}

test "an initial whose size is not its component's is refused" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    const initial: Paddle = .{ .speed = 7, .visits = 2 };
    var d = paddleDesc();
    d.initial = &initial;
    d.initial_size = @sizeOf(Paddle) + 1;
    var cid: Cid = 0;
    try testing.expectEqual(R.code(error.InvalidArgument), f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
}

test "initial answers the bytes a type's nodes are born with in a component it carries, and null otherwise" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    const born: Paddle = .{ .speed = 7, .visits = 2 };
    var d = paddleDesc();
    d.initial = &born;
    d.initial_size = @sizeOf(Paddle);
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    const fields_cid = findType(stateOf(f.types.ref).?, cid).?.columns[0];
    const bytes: *const Paddle = @ptrCast(@alignCast(f.types.ref.?.initial.?(f.types.ref, cid, fields_cid).?));
    try testing.expectEqual(born, bytes.*);
    try testing.expect(f.types.ref.?.initial.?(f.types.ref, cid, 999) == null);
}

test "initial bytes without fields are refused" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    const initial: Paddle = .{ .speed = 7, .visits = 2 };
    var d = paddleDesc();
    d.fields_size = 0;
    d.initial = &initial;
    d.initial_size = @sizeOf(Paddle);
    var cid: Cid = 0;
    try testing.expectEqual(R.code(error.InvalidArgument), f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
}

test "the engine node types part registers every engine node type through the node types it is bound to" {
    var types: zsub.For(abi_framework.c.ke_node_types) = undefined;
    try types.init();
    defer types.deinit();
    _ = types.when(.register_type).writesFresh(2);
    const p = &parts[2];
    const bound_types = [_]?*anyopaque{types.api()};
    const bound = [_]abi_part.c.ke_part_bound{.{ .instances = @ptrCast(&bound_types), .count = 1 }};
    var owner: abi_part.c.ke_owner = undefined;
    try R.check(p.create.?(p, &bound[0], null, &owner));
    try types.received(.register_type).times(abi_engine_node_types.c.KE_ENGINE_NODE_TYPE_COUNT);
    try testing.expectEqual(@as(usize, 0), p.provides_count);
    owner.destroy.?(owner.ref);
}

test "the node types leak nothing" {
    try heap.expectNoLeaks();
}
