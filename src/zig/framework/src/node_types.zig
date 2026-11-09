//! Node types: each behaviour of a registered type runs as one exclusive system of its phase,
//! walking the nodes of the type through a `ke_node_ctx`, and events are entities that live from
//! the tick they are raised in to the next PreUpdate.

const std = @import("std");

const abi_ecs = @import("abi_ecs");
const abi_framework = @import("abi_framework");
const abi_framework_components = @import("abi_framework_components");
const abi_input_actions = @import("abi_input_actions");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const abi_scene_tree = @import("abi_scene_tree");
const R = @import("result").Result(.{});
const log = std.log.scoped(.framework);
const heap = @import("heap");

const Entity = abi_ecs.c.ke_entity;
const Cid = abi_ecs.c.ke_component_id;
const invalid = abi_ecs.c.KE_ENTITY_INVALID;
const status_name = "node_status";
const base_type_name = "node";
const prototype_alignment: std.mem.Alignment = .@"16";

const NodeStatus = extern struct { readied: u8 };

const Kind = enum { ready, update, fixed_update, on };

/// One registered behaviour: the system it runs as, and the query that system reads through. The
/// runtime keeps its address as the system's user data and reads `terms` while registering it.
const Behaviour = struct {
    owner: *Type,
    kind: Kind,
    run: abi_framework.c.ke_node_behaviour_fn,
    event: ?*Event = null,
    system: abi_runtime.c.ke_system_id = 0,
    name: [:0]u8,
    terms: []abi_runtime.c.ke_component_access,
    event_terms: [1]abi_runtime.c.ke_component_access = undefined,
    queries: [2]abi_runtime.c.ke_query_decl = undefined,
};

/// A registered node type: its tag, the component ids its nodes carry, the fields first when it
/// has them, with the size and the default-seeded bytes of each, and the behaviours it runs. A
/// behaviour's query reads the tag first, so a component's column is its index plus one.
const Type = struct {
    state: *State,
    tag: Cid,
    has_fields: bool,
    columns: []Cid,
    sizes: []usize,
    prototypes: [][]align(16) u8,
    user_data: ?*anyopaque,
    behaviours: std.ArrayList(*Behaviour) = .empty,
};

/// A registered event type, and the PreUpdate system that destroys the events of the last tick.
const Event = struct {
    cid: Cid,
    size: usize,
    system: abi_runtime.c.ke_system_id = 0,
    name: [:0]u8,
    terms: [1]abi_runtime.c.ke_component_access = undefined,
    queries: [1]abi_runtime.c.ke_query_decl = undefined,
};

/// Created by `ke_node_types_create` and freed by `vtDestroy`, which unregisters every system the
/// types and events registered first. It owns the types and events, whose addresses the runtime
/// holds as user data.
const State = struct {
    api: abi_framework.c.ke_node_types,
    runtime: *abi_runtime.c.ke_runtime,
    ecs: *abi_ecs.c.ke_ecs,
    tree: *abi_scene_tree.c.ke_scene_tree,
    actions: ?*abi_input_actions.c.ke_input_actions,
    status_cid: Cid,
    name_cid: Cid,
    types: std.ArrayList(*Type) = .empty,
    events: std.ArrayList(*Event) = .empty,
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

/// Slot `next`. Moves to the next node of the type; a ready behaviour skips the nodes already
/// readied and marks each one it moves to; an on handler moves through every node for one event,
/// then to the next event.
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
        if (w.behaviour.kind == .ready) {
            const status: *NodeStatus = @ptrCast(column(w, w.behaviour.owner.columns.len + 1, @sizeOf(NodeStatus)) orelse continue);
            if (status.readied != 0) continue;
            status.readied = 1;
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
    const status: NodeStatus = .{ .readied = 0 };
    rc = commands.attach.?(commands, node, s.status_cid, &status, @sizeOf(NodeStatus));
    if (rc != R.ok) return rc;
    out.* = node;
    return R.ok;
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
    return s.tree.destroy_node_deferred.?(s.tree, node, w.api.commands);
}

/// Slot `exit`. Forwards the request to the runtime.
fn exit(ctx: ?*abi_framework.c.ke_node_ctx) callconv(.c) void {
    const w = walkOf(ctx) orelse return;
    const rt = w.behaviour.owner.state.runtime;
    rt.request_exit.?(rt);
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
    const rc = commands.?.spawn.?(commands, &entity);
    if (rc != R.ok) return rc;
    return commands.?.attach.?(commands, entity, e.cid, data, size);
}

fn viewOf(sys: ?*abi_runtime.c.ke_system_ctx, query: u32) []const abi_ecs.c.ke_ecs_segment {
    var count: usize = 0;
    const segs = sys.?.view.?(sys, query, &count) orelse return &.{};
    return segs[0..count];
}

/// The body of every behaviour system: builds the walk over the system's queries and hands it to
/// the behaviour once.
fn behaviourSystem(sys: ?*abi_runtime.c.ke_system_ctx, user: ?*anyopaque, dt: f32) callconv(.c) abi_result.c.ke_result {
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
            .destroy = &destroy,
            .raise = &raise,
            .exit = &exit,
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
fn clearEvents(sys: ?*abi_runtime.c.ke_system_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const commands = sys.?.commands;
    for (viewOf(sys, 0)) |seg| {
        for (seg.entities.?[0..seg.count]) |e| {
            const rc = commands.?.despawn.?(commands, e);
            if (rc != R.ok) return rc;
        }
    }
    return R.ok;
}

fn phaseOf(kind: Kind) abi_runtime.c.ke_phase {
    return switch (kind) {
        .ready => abi_runtime.c.KE_PHASE_PRE_UPDATE,
        .update => abi_runtime.c.KE_PHASE_UPDATE,
        .fixed_update => abi_runtime.c.KE_PHASE_FIXED_UPDATE,
        .on => abi_runtime.c.KE_PHASE_POST_UPDATE,
    };
}

fn freeBehaviour(b: *Behaviour) void {
    heap.gpa.free(b.name);
    heap.gpa.free(b.terms);
    heap.gpa.destroy(b);
}

fn freeType(s: *State, t: *Type) void {
    for (t.behaviours.items) |b| {
        if (b.system != 0) _ = s.runtime.unregister_system.?(s.runtime, b.system);
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
    };
    const name = std.fmt.allocPrintSentinel(heap.gpa, "{s}.{s}{s}{s}", .{ type_name, suffix, if (event) |_| "." else "", if (event) |e| e.name else "" }, 0) catch return error.OutOfMemory;
    errdefer heap.gpa.free(name);
    const extra: usize = if (kind == .ready) 2 else 1;
    const terms = heap.gpa.alloc(abi_runtime.c.ke_component_access, t.columns.len + extra) catch return error.OutOfMemory;
    errdefer heap.gpa.free(terms);
    terms[0] = .{ .cid = t.tag, .access = abi_runtime.c.KE_ACCESS_READ };
    for (t.columns, 1..) |c, i| terms[i] = .{ .cid = c, .access = abi_runtime.c.KE_ACCESS_WRITE };
    if (kind == .ready) terms[t.columns.len + 1] = .{ .cid = s.status_cid, .access = abi_runtime.c.KE_ACCESS_WRITE };

    const b = heap.gpa.create(Behaviour) catch return error.OutOfMemory;
    errdefer heap.gpa.destroy(b);
    b.* = .{ .owner = t, .kind = kind, .run = run, .event = event, .name = name, .terms = terms };

    var params = std.mem.zeroes(abi_runtime.c.ke_runtime_system_params);
    params.name = name.ptr;
    params.phase = phaseOf(kind);
    params.user_data = b;
    params.execute = behaviourSystem;
    params.exclusive = true;
    if (event) |e| {
        b.event_terms = .{.{ .cid = e.cid, .access = abi_runtime.c.KE_ACCESS_READ }};
        b.queries = .{
            .{ .terms = &b.event_terms, .term_count = 1 },
            .{ .terms = terms.ptr, .term_count = @intCast(terms.len) },
        };
        params.query_count = 2;
    } else {
        b.queries[0] = .{ .terms = terms.ptr, .term_count = @intCast(terms.len) };
        params.query_count = 1;
    }
    params.queries = &b.queries;
    t.behaviours.append(heap.gpa, b) catch return error.OutOfMemory;
    errdefer _ = t.behaviours.pop();
    try R.check(s.runtime.register_system.?(s.runtime, &params, &b.system));
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
    const tag: abi_ecs.c.ke_component_params = .{ .name = tag_name.ptr, .size = 0, .alignment = 0 };
    try R.check(s.ecs.component_register.?(s.ecs, &tag, &t.tag));
    if (desc.fields_size != 0) {
        const fields: abi_ecs.c.ke_component_params = .{ .name = name, .size = desc.fields_size, .alignment = desc.fields_alignment, .fields = desc.fields, .field_count = desc.field_count };
        try R.check(s.ecs.component_register.?(s.ecs, &fields, &t.columns[0]));
        t.sizes[0] = desc.fields_size;
        t.prototypes[0] = try prototypeOf(desc.fields_size, desc.initial, desc.initial_size, name);
    }

    const type_name = std.mem.span(name);
    if (desc.ready != null) try addBehaviour(s, t, .ready, desc.ready, null, type_name);
    if (desc.update != null) try addBehaviour(s, t, .update, desc.update, null, type_name);
    if (desc.fixed_update != null) try addBehaviour(s, t, .fixed_update, desc.fixed_update, null, type_name);
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

fn registerEvent(s: *State, params: *const abi_ecs.c.ke_component_params) R.Error!Cid {
    const name = params.name orelse return error.InvalidArgument;
    const e = heap.gpa.create(Event) catch return error.OutOfMemory;
    errdefer heap.gpa.destroy(e);
    e.* = .{ .cid = 0, .size = params.size, .name = heap.gpa.dupeZ(u8, std.mem.span(name)) catch return error.OutOfMemory };
    errdefer heap.gpa.free(e.name);
    try R.check(s.ecs.component_register.?(s.ecs, params, &e.cid));
    e.terms = .{.{ .cid = e.cid, .access = abi_runtime.c.KE_ACCESS_WRITE }};
    e.queries = .{.{ .terms = &e.terms, .term_count = 1 }};

    const system_name = std.fmt.allocPrintSentinel(heap.gpa, "{s}.clear", .{e.name}, 0) catch return error.OutOfMemory;
    defer heap.gpa.free(system_name);
    var p = std.mem.zeroes(abi_runtime.c.ke_runtime_system_params);
    p.name = system_name.ptr;
    p.phase = abi_runtime.c.KE_PHASE_PRE_UPDATE;
    p.user_data = e;
    p.execute = clearEvents;
    p.queries = &e.queries;
    p.query_count = 1;
    try R.check(s.runtime.register_system.?(s.runtime, &p, &e.system));
    errdefer _ = s.runtime.unregister_system.?(s.runtime, e.system);
    s.events.append(heap.gpa, e) catch return error.OutOfMemory;
    return e.cid;
}

/// Slot `register_event`.
fn vtRegisterEvent(self: ?*abi_framework.c.ke_node_types, params_in: ?*const abi_ecs.c.ke_component_params, out_event: ?*Cid) callconv(.c) abi_result.c.ke_result {
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
    for (s.types.items) |t| freeType(s, t);
    s.types.deinit(heap.gpa);
    for (s.events.items) |e| {
        _ = s.runtime.unregister_system.?(s.runtime, e.system);
        heap.gpa.free(e.name);
        heap.gpa.destroy(e);
    }
    s.events.deinit(heap.gpa);
    heap.gpa.destroy(s);
}

fn create(runtime: *abi_runtime.c.ke_runtime, ecs: *abi_ecs.c.ke_ecs, tree: *abi_scene_tree.c.ke_scene_tree, actions: ?*abi_input_actions.c.ke_input_actions) R.Error!abi_framework.c.ke_node_types_handle {
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
        const params: abi_ecs.c.ke_component_params = .{ .name = status_name, .size = @sizeOf(NodeStatus), .alignment = @alignOf(NodeStatus) };
        try R.check(ecs.component_register.?(ecs, &params, &status_cid));
    }

    const s = heap.gpa.create(State) catch return error.OutOfMemory;
    s.* = .{
        .api = .{ .register_type = &vtRegisterType, .register_event = &vtRegisterEvent, .spawn = &vtSpawn, .carries = &vtCarries, .find_type = &vtFindType, .find_component = &vtFindComponent, .initial = &vtInitial },
        .runtime = runtime,
        .ecs = ecs,
        .tree = tree,
        .actions = actions,
        .status_cid = status_cid,
        .name_cid = name_meta.cid,
    };
    s.api.handle = s;
    errdefer vtDestroy(&s.api);
    var base = std.mem.zeroes(abi_framework.c.ke_node_type_desc);
    base.name = base_type_name;
    _ = try registerType(s, &base);
    return .{ .ref = &s.api, .destroy = vtDestroy };
}

/// Factory. A null runtime, ecs, scene tree or out handle fails as an invalid argument; an ecs
/// without the scene tree components fails as not found; a refused registration fails with the
/// ecs's code. Each leaves the handle zeroed.
export fn ke_node_types_create(
    runtime_in: ?*abi_runtime.c.ke_runtime,
    ecs_in: ?*abi_ecs.c.ke_ecs,
    tree_in: ?*abi_scene_tree.c.ke_scene_tree,
    actions: ?*abi_input_actions.c.ke_input_actions,
    out_types: ?*abi_framework.c.ke_node_types_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_types orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_framework.c.ke_node_types_handle);
    const runtime = runtime_in orelse return R.code(error.InvalidArgument);
    const ecs = ecs_in orelse return R.code(error.InvalidArgument);
    const tree = tree_in orelse return R.code(error.InvalidArgument);
    out.* = create(runtime, ecs, tree, actions) catch |err| return R.code(err);
    return R.ok;
}

const testing = std.testing;
const zsub = @import("zsub");

const Paddle = extern struct { speed: f32, visits: u32 };
const Goal = extern struct { left: u8 };
const transform2d_cid: Cid = 50;
const name_cid: Cid = 40;

var registered: [8]abi_runtime.c.ke_runtime_system_params = undefined;
var registered_count: usize = 0;

fn recordSystem(args: zsub.For(abi_runtime.c.ke_runtime).Args(.register_system)) abi_result.c.ke_result {
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
    rt: zsub.For(abi_runtime.c.ke_runtime) = undefined,
    tree: zsub.For(abi_scene_tree.c.ke_scene_tree) = undefined,
    types: abi_framework.c.ke_node_types_handle = undefined,

    fn init(f: *Fixture) !void {
        registered_count = 0;
        tag_count = 0;
        try f.ecs.init();
        try f.rt.init();
        try f.tree.init();
        _ = f.ecs.when(.component_lookup).does(lookupComponent);
        _ = f.ecs.when(.component_register).does(registerComponent);
        _ = f.rt.when(.register_system).does(recordSystem);
        try R.check(ke_node_types_create(f.rt.api(), f.ecs.api(), f.tree.api(), null, &f.types));
    }

    fn deinit(f: *Fixture) void {
        f.types.destroy.?(f.types.ref);
        f.tree.deinit();
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
    sys: abi_runtime.c.ke_system_ctx = undefined,
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

    fn view(sys: ?*abi_runtime.c.ke_system_ctx, query: u32, out_count: ?*usize) callconv(.c) ?[*]const abi_ecs.c.ke_ecs_segment {
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

fn runSystem(params: abi_runtime.c.ke_runtime_system_params, rows: *Rows) !void {
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
    try testing.expectEqual(abi_runtime.c.KE_PHASE_PRE_UPDATE, registered[0].phase);
    try testing.expectEqual(abi_runtime.c.KE_PHASE_UPDATE, registered[1].phase);
    try testing.expectEqual(abi_runtime.c.KE_PHASE_FIXED_UPDATE, registered[2].phase);
    for (registered[0..3]) |p| try testing.expect(p.exclusive);
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
    try R.check(ke_node_types_create(f.rt.api(), f.ecs.api(), f.tree.api(), actions.api(), &with_actions));
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

fn askExit(ctx: ?*abi_framework.c.ke_node_ctx, _: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    ctx.?.exit.?(ctx);
    return R.ok;
}

test "exit forwards the request to the runtime" {
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
    try f.rt.received(.request_exit).times(1);
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
    const goal: abi_ecs.c.ke_component_params = .{ .name = "pong.goal", .size = @sizeOf(Goal), .alignment = 1 };
    var goal_cid: Cid = 0;
    try R.check(f.types.ref.?.register_event.?(f.types.ref, &goal, &goal_cid));
    const events = [_]Cid{goal_cid};
    var d = paddleDesc();
    d.events = &events;
    d.event_count = 1;
    d.on = countGoals;
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    try testing.expectEqual(abi_runtime.c.KE_PHASE_PRE_UPDATE, registered[0].phase);
    try testing.expectEqual(abi_runtime.c.KE_PHASE_POST_UPDATE, registered[1].phase);
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
    const goal: abi_ecs.c.ke_component_params = .{ .name = "pong.goal", .size = @sizeOf(Goal), .alignment = 1 };
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
    try commands.received(.attach).where(zsub.argIs(1, @as(Entity, 30))).times(1);
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
    try testing.expectEqual(@as(u32, 2), registered[0].queries.?[0].term_count);
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
    const goal: abi_ecs.c.ke_component_params = .{ .name = "pong.goal", .size = @sizeOf(Goal), .alignment = 1 };
    var goal_cid: Cid = 0;
    try R.check(f.types.ref.?.register_event.?(f.types.ref, &goal, &goal_cid));
    var d = paddleDesc();
    d.update = countVisits;
    d.fixed_update = countVisits;
    var cid: Cid = 0;
    try R.check(f.types.ref.?.register_type.?(f.types.ref, &d, &cid));
    f.types.destroy.?(f.types.ref);
    try f.rt.received(.unregister_system).times(3);
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

test "the node types leak nothing" {
    try heap.expectNoLeaks();
}
