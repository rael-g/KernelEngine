const std = @import("std");

const c = @import("c.zig").c;
const heap = @import("heap.zig");

const E = @import("kerror").Errors(c);

/// Longest script type name the host stores.
const name_max = 96;

/// Components one script type may declare. A type is a component set, and a set
/// this wide already exceeds what a query can carry, so the ceiling is reached
/// long after the one that actually binds.
const components_max = 16;

const default_max_types = 64;
const default_max_instances = 4096;

const ScriptType = struct {
    name: [name_max]u8,
    name_len: usize,
    components: [components_max]c.ke_component_id,
    component_count: u32,
    reach: c.ke_script_reach,
    instance_count: u32,
};

const Binding = struct {
    entity: c.ke_entity,
    type_id: c.ke_script_type_id,
    instance: ?*anyopaque,
};

const State = struct {
    api: c.ke_script_host,
    ecs: *c.ke_ecs,
    hierarchy_cid: c.ke_component_id,
    name_cid: c.ke_component_id,

    types: []ScriptType,
    type_count: u32,

    bindings: []Binding,
    binding_count: u32,
};

fn stateOf(self: *c.ke_script_host) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn orDefault(v: u32, d: u32) u32 {
    return if (v == 0) d else v;
}

fn typeAt(s: *State, id: c.ke_script_type_id) ?*ScriptType {
    if (id == c.KE_SCRIPT_TYPE_NONE or id > s.type_count) return null;
    return &s.types[id - 1];
}

fn bindingOf(s: *State, entity: c.ke_entity) ?*Binding {
    for (s.bindings[0..s.binding_count]) |*b|
        if (b.entity == entity) return b;
    return null;
}

fn getHierarchy(s: *State, e: c.ke_entity) ?*c.ke_hierarchy_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.hierarchy_cid)));
}

fn getName(s: *State, e: c.ke_entity) []const u8 {
    const raw = s.ecs.component_get.?(s.ecs, e, s.name_cid) orelse return &[_]u8{};
    const comp: *const c.ke_name_component = @ptrCast(@alignCast(raw));
    return std.mem.sliceTo(&comp.name, 0);
}

fn matches(s: *State, entity: c.ke_entity, type_id: c.ke_script_type_id, wanted: []const u8) bool {
    const b = bindingOf(s, entity) orelse return false;
    if (b.type_id != type_id) return false;
    if (wanted.len == 0) return true;
    return std.mem.eql(u8, getName(s, entity), wanted);
}

fn registerType(
    self_in: ?*c.ke_script_host,
    name_in: [*c]const u8,
    components_in: [*c]const c.ke_component_id,
    component_count: u32,
    reach: c.ke_script_reach,
    out_id: [*c]c.ke_script_type_id,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "script host is null", @src());
        return false;
    };
    if (name_in == null or out_id == null) {
        E.fail(out_error, .invalid_argument, "type name and out_id are required", @src());
        return false;
    }
    const s = stateOf(self);
    const name = std.mem.span(name_in);
    if (name.len == 0 or name.len >= name_max) {
        E.fail(out_error, .invalid_argument, "script type name is empty or too long", @src());
        return false;
    }
    if (component_count > components_max) {
        E.fail(out_error, .invalid_argument, "script type declares more components than a type may carry", @src());
        return false;
    }
    if (component_count > 0 and components_in == null) {
        E.fail(out_error, .invalid_argument, "component count is non-zero but no components were given", @src());
        return false;
    }

    for (s.types[0..s.type_count], 0..) |*t, i| {
        if (!std.mem.eql(u8, t.name[0..t.name_len], name)) continue;
        if (t.component_count != component_count or t.reach != reach) {
            E.fail(out_error, .already_exists, "script type already registered with a different description", @src());
            return false;
        }
        for (0..component_count) |k| {
            if (t.components[k] == components_in[k]) continue;
            E.fail(out_error, .already_exists, "script type already registered with different components", @src());
            return false;
        }
        out_id.* = @intCast(i + 1);
        return true;
    }

    if (s.type_count == s.types.len) {
        E.fail(out_error, .out_of_memory, "script type table is full", @src());
        return false;
    }

    var t = ScriptType{
        .name = undefined,
        .name_len = name.len,
        .components = undefined,
        .component_count = component_count,
        .reach = reach,
        .instance_count = 0,
    };
    @memcpy(t.name[0..name.len], name);
    for (0..component_count) |k| t.components[k] = components_in[k];

    s.types[s.type_count] = t;
    s.type_count += 1;
    out_id.* = s.type_count;
    return true;
}

fn typeLookup(
    self_in: ?*c.ke_script_host,
    name_in: [*c]const u8,
    out_id: [*c]c.ke_script_type_id,
) callconv(.c) bool {
    const self = self_in orelse return false;
    if (name_in == null or out_id == null) return false;
    const s = stateOf(self);
    const name = std.mem.span(name_in);
    for (s.types[0..s.type_count], 0..) |*t, i| {
        if (!std.mem.eql(u8, t.name[0..t.name_len], name)) continue;
        out_id.* = @intCast(i + 1);
        return true;
    }
    return false;
}

fn typeComponents(
    self_in: ?*c.ke_script_host,
    type_id: c.ke_script_type_id,
    out_count: [*c]u32,
) callconv(.c) [*c]const c.ke_component_id {
    const self = self_in orelse return null;
    const s = stateOf(self);
    const t = typeAt(s, type_id) orelse {
        if (out_count != null) out_count.* = 0;
        return null;
    };
    if (out_count != null) out_count.* = t.component_count;
    return &t.components;
}

fn typeReach(self_in: ?*c.ke_script_host, type_id: c.ke_script_type_id) callconv(.c) c.ke_script_reach {
    const self = self_in orelse return c.KE_SCRIPT_REACH_ANY;
    const s = stateOf(self);
    const t = typeAt(s, type_id) orelse return c.KE_SCRIPT_REACH_ANY;
    return t.reach;
}

fn bind(
    self_in: ?*c.ke_script_host,
    entity: c.ke_entity,
    type_id: c.ke_script_type_id,
    instance: ?*anyopaque,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "script host is null", @src());
        return false;
    };
    const s = stateOf(self);
    const t = typeAt(s, type_id) orelse {
        E.fail(out_error, .not_found, "script type id was never registered", @src());
        return false;
    };
    if (entity == c.KE_ENTITY_INVALID) {
        E.fail(out_error, .invalid_argument, "cannot bind an instance to an invalid entity", @src());
        return false;
    }
    if (bindingOf(s, entity) != null) {
        E.fail(out_error, .already_exists, "entity already carries a script instance", @src());
        return false;
    }
    if (s.binding_count == s.bindings.len) {
        E.fail(out_error, .out_of_memory, "script instance table is full", @src());
        return false;
    }

    s.bindings[s.binding_count] = .{ .entity = entity, .type_id = type_id, .instance = instance };
    s.binding_count += 1;
    t.instance_count += 1;
    return true;
}

fn unbind(self_in: ?*c.ke_script_host, entity: c.ke_entity) callconv(.c) void {
    const self = self_in orelse return;
    const s = stateOf(self);
    for (s.bindings[0..s.binding_count], 0..) |*b, i| {
        if (b.entity != entity) continue;
        if (typeAt(s, b.type_id)) |t| t.instance_count -= 1;
        s.bindings[i] = s.bindings[s.binding_count - 1];
        s.binding_count -= 1;
        return;
    }
}

fn instanceOf(
    self_in: ?*c.ke_script_host,
    entity: c.ke_entity,
    out_type: [*c]c.ke_script_type_id,
    out_instance: [*c]?*anyopaque,
) callconv(.c) bool {
    const self = self_in orelse return false;
    const s = stateOf(self);
    const b = bindingOf(s, entity) orelse return false;
    if (out_type != null) out_type.* = b.type_id;
    if (out_instance != null) out_instance.* = b.instance;
    return true;
}

fn instanceCount(self_in: ?*c.ke_script_host, type_id: c.ke_script_type_id) callconv(.c) u32 {
    const self = self_in orelse return 0;
    const s = stateOf(self);
    const t = typeAt(s, type_id) orelse return 0;
    return t.instance_count;
}

fn descendantOf(s: *State, parent: c.ke_entity, type_id: c.ke_script_type_id, wanted: []const u8, found: *c.ke_entity) bool {
    const h = getHierarchy(s, parent) orelse return false;
    var child = h.first_child;
    while (child != c.KE_ENTITY_INVALID) {
        if (matches(s, child, type_id, wanted)) {
            if (found.* != c.KE_ENTITY_INVALID) return true;
            found.* = child;
        }
        if (descendantOf(s, child, type_id, wanted, found)) return true;
        child = if (getHierarchy(s, child)) |ch| ch.next_sibling else c.KE_ENTITY_INVALID;
    }
    return false;
}

fn resolveDescendant(
    self_in: ?*c.ke_script_host,
    entity: c.ke_entity,
    type_id: c.ke_script_type_id,
    name_in: [*c]const u8,
) callconv(.c) c.ke_entity {
    const self = self_in orelse return c.KE_ENTITY_INVALID;
    const s = stateOf(self);
    const wanted = if (name_in == null) &[_]u8{} else std.mem.span(name_in);

    var found: c.ke_entity = c.KE_ENTITY_INVALID;
    if (descendantOf(s, entity, type_id, wanted, &found)) return c.KE_ENTITY_INVALID;
    return found;
}

fn resolveAncestor(
    self_in: ?*c.ke_script_host,
    entity: c.ke_entity,
    type_id: c.ke_script_type_id,
    name_in: [*c]const u8,
) callconv(.c) c.ke_entity {
    const self = self_in orelse return c.KE_ENTITY_INVALID;
    const s = stateOf(self);
    const wanted = if (name_in == null) &[_]u8{} else std.mem.span(name_in);

    var cur = if (getHierarchy(s, entity)) |h| h.parent else c.KE_ENTITY_INVALID;
    while (cur != c.KE_ENTITY_INVALID) {
        if (matches(s, cur, type_id, wanted)) return cur;
        cur = if (getHierarchy(s, cur)) |h| h.parent else c.KE_ENTITY_INVALID;
    }
    return c.KE_ENTITY_INVALID;
}

fn destroy(self_in: ?*c.ke_script_host) callconv(.c) void {
    const self = self_in orelse return;
    const s = stateOf(self);
    heap.gpa.free(s.bindings);
    heap.gpa.free(s.types);
    heap.gpa.destroy(s);
}

pub export fn ke_script_host_create(
    ecs_in: ?*c.ke_ecs,
    params: [*c]const c.ke_script_host_params,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_script_host_handle {
    const null_handle = std.mem.zeroes(c.ke_script_host_handle);

    const ecs = ecs_in orelse {
        E.fail(out_error, .invalid_argument, "script host requires an ecs", @src());
        return null_handle;
    };
    if (ecs.component_lookup == null or ecs.component_get == null) {
        E.fail(out_error, .invalid_argument, "ecs does not expose component lookup", @src());
        return null_handle;
    }

    var hierarchy_meta: c.ke_component_meta = undefined;
    var name_meta: c.ke_component_meta = undefined;
    if (!ecs.component_lookup.?(ecs, c.KE_COMPONENT_NAME_HIERARCHY, &hierarchy_meta, null) or
        !ecs.component_lookup.?(ecs, c.KE_COMPONENT_NAME_NAME, &name_meta, null))
    {
        E.fail(out_error, .not_found, "hierarchy and name components are not registered; create a scene tree first", @src());
        return null_handle;
    }

    const n_types = if (params != null) orDefault(params.*.max_types, default_max_types) else default_max_types;
    const n_instances = if (params != null) orDefault(params.*.max_instances, default_max_instances) else default_max_instances;

    const s = heap.gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "script host allocation failed", @src());
        return null_handle;
    };

    s.types = heap.gpa.alloc(ScriptType, n_types) catch {
        E.fail(out_error, .out_of_memory, "script type table allocation failed", @src());
        heap.gpa.destroy(s);
        return null_handle;
    };
    s.bindings = heap.gpa.alloc(Binding, n_instances) catch {
        E.fail(out_error, .out_of_memory, "script instance table allocation failed", @src());
        heap.gpa.free(s.types);
        heap.gpa.destroy(s);
        return null_handle;
    };

    s.ecs = ecs;
    s.hierarchy_cid = hierarchy_meta.cid;
    s.name_cid = name_meta.cid;
    s.type_count = 0;
    s.binding_count = 0;

    s.api = .{
        .handle = s,
        .register_type = &registerType,
        .type_lookup = &typeLookup,
        .type_components = &typeComponents,
        .type_reach = &typeReach,
        .bind = &bind,
        .unbind = &unbind,
        .instance_of = &instanceOf,
        .instance_count = &instanceCount,
        .resolve_descendant = &resolveDescendant,
        .resolve_ancestor = &resolveAncestor,
    };

    return .{ .ref = &s.api, .destroy = &destroy };
}

const testing = std.testing;
const scene_tree = @import("scene_tree.zig");

const Harness = struct {
    tree: scene_tree.Fixture,
    handle: c.ke_script_host_handle,

    fn init(self: *Harness) !void {
        try self.tree.init();
        self.handle = ke_script_host_create(&self.tree.ecs.vtable, null, null);
        try testing.expect(self.handle.ref != null);
    }

    fn deinit(self: *Harness) void {
        if (self.handle.destroy) |d| d(self.handle.ref);
        self.tree.deinit();
    }

    fn host(self: *Harness) *c.ke_script_host {
        return self.handle.ref;
    }

    fn declare(self: *Harness, name: [*c]const u8, reach: c.ke_script_reach) !c.ke_script_type_id {
        var id: c.ke_script_type_id = c.KE_SCRIPT_TYPE_NONE;
        const components = [_]c.ke_component_id{ 1, 2 };
        try testing.expect(self.host().register_type.?(self.host(), name, &components, components.len, reach, &id, null));
        return id;
    }
};

test "a type registered twice under one name is the same type" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const first = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);
    const again = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);

    try testing.expectEqual(first, again);
}

test "a type re-registered with a different reach is refused" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    _ = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);

    var id: c.ke_script_type_id = c.KE_SCRIPT_TYPE_NONE;
    const components = [_]c.ke_component_id{ 1, 2 };
    try testing.expect(!h.host().register_type.?(h.host(), "pong.paddle", &components, components.len, c.KE_SCRIPT_REACH_ANY, &id, null));
}

test "an unregistered type name resolves to nothing" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    var id: c.ke_script_type_id = 12345;
    try testing.expect(!h.host().type_lookup.?(h.host(), "pong.nobody", &id));
}

test "an unknown type reaches anywhere, because refusing to parallelise it is the safe answer" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    try testing.expectEqual(@as(c.ke_script_reach, c.KE_SCRIPT_REACH_ANY), h.host().type_reach.?(h.host(), 9999));
    try testing.expectEqual(@as(c.ke_script_reach, c.KE_SCRIPT_REACH_ANY), h.host().type_reach.?(h.host(), c.KE_SCRIPT_TYPE_NONE));
}

test "a type reports the components it was registered with" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);

    var count: u32 = 0;
    const comps = h.host().type_components.?(h.host(), id, &count);
    try testing.expectEqual(@as(u32, 2), count);
    try testing.expectEqual(@as(c.ke_component_id, 1), comps[0]);
    try testing.expectEqual(@as(c.ke_component_id, 2), comps[1]);
}

test "an entity carries the instance it was bound to" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);
    const e = h.tree.create("Left", 0);
    var marker: u32 = 7;

    try testing.expect(h.host().bind.?(h.host(), e, id, &marker, null));

    var out_type: c.ke_script_type_id = c.KE_SCRIPT_TYPE_NONE;
    var out_instance: ?*anyopaque = null;
    try testing.expect(h.host().instance_of.?(h.host(), e, &out_type, &out_instance));
    try testing.expectEqual(id, out_type);
    try testing.expectEqual(@as(?*anyopaque, &marker), out_instance);
}

test "binding over an existing instance is refused rather than dropping it silently" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);
    const e = h.tree.create("Left", 0);
    var first: u32 = 1;
    var second: u32 = 2;

    try testing.expect(h.host().bind.?(h.host(), e, id, &first, null));
    try testing.expect(!h.host().bind.?(h.host(), e, id, &second, null));

    var out_instance: ?*anyopaque = null;
    _ = h.host().instance_of.?(h.host(), e, null, &out_instance);
    try testing.expectEqual(@as(?*anyopaque, &first), out_instance);
}

test "an entity nobody bound has no instance" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const e = h.tree.create("Scenery", 0);
    try testing.expect(!h.host().instance_of.?(h.host(), e, null, null));
}

test "instance count follows bind and unbind" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const id = try h.declare("pong.paddle", c.KE_SCRIPT_REACH_SELF);
    const a = h.tree.create("Left", 0);
    const b = h.tree.create("Right", 0);
    var ma: u32 = 1;
    var mb: u32 = 2;

    try testing.expectEqual(@as(u32, 0), h.host().instance_count.?(h.host(), id));
    try testing.expect(h.host().bind.?(h.host(), a, id, &ma, null));
    try testing.expect(h.host().bind.?(h.host(), b, id, &mb, null));
    try testing.expectEqual(@as(u32, 2), h.host().instance_count.?(h.host(), id));

    h.host().unbind.?(h.host(), a);
    try testing.expectEqual(@as(u32, 1), h.host().instance_count.?(h.host(), id));
    try testing.expect(!h.host().instance_of.?(h.host(), a, null, null));
}

test "a descendant of the wanted type is found through intermediate nodes" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const holder = h.tree.create("Sounds", ball);
    const hit = h.tree.create("HitSound", holder);
    var marker: u32 = 1;
    try testing.expect(h.host().bind.?(h.host(), hit, audio, &marker, null));

    try testing.expectEqual(hit, h.host().resolve_descendant.?(h.host(), ball, audio, ""));
}

test "a descendant named by the borrow is picked out of several of its type" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const hit = h.tree.create("HitSound", ball);
    const score = h.tree.create("ScoreSound", ball);
    var m1: u32 = 1;
    var m2: u32 = 2;
    try testing.expect(h.host().bind.?(h.host(), hit, audio, &m1, null));
    try testing.expect(h.host().bind.?(h.host(), score, audio, &m2, null));

    try testing.expectEqual(score, h.host().resolve_descendant.?(h.host(), ball, audio, "ScoreSound"));
}

test "an unnamed borrow answered by two nodes resolves to nothing instead of guessing" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const hit = h.tree.create("HitSound", ball);
    const score = h.tree.create("ScoreSound", ball);
    var m1: u32 = 1;
    var m2: u32 = 2;
    try testing.expect(h.host().bind.?(h.host(), hit, audio, &m1, null));
    try testing.expect(h.host().bind.?(h.host(), score, audio, &m2, null));

    try testing.expectEqual(@as(c.ke_entity, c.KE_ENTITY_INVALID), h.host().resolve_descendant.?(h.host(), ball, audio, ""));
}

test "a node of the wanted type outside the subtree is not a descendant" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const audio = try h.declare("engine.audio_player", c.KE_SCRIPT_REACH_SELF);
    const ball = h.tree.create("Ball", 0);
    const elsewhere = h.tree.create("Music", 0);
    var marker: u32 = 1;
    try testing.expect(h.host().bind.?(h.host(), elsewhere, audio, &marker, null));

    try testing.expectEqual(@as(c.ke_entity, c.KE_ENTITY_INVALID), h.host().resolve_descendant.?(h.host(), ball, audio, ""));
}

test "the nearest ancestor of the wanted type wins over a further one" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const field = try h.declare("pong.field", c.KE_SCRIPT_REACH_ANY);
    const outer = h.tree.create("Outer", 0);
    const inner = h.tree.create("Inner", outer);
    const leaf = h.tree.create("Leaf", inner);
    var m1: u32 = 1;
    var m2: u32 = 2;
    try testing.expect(h.host().bind.?(h.host(), outer, field, &m1, null));
    try testing.expect(h.host().bind.?(h.host(), inner, field, &m2, null));

    try testing.expectEqual(inner, h.host().resolve_ancestor.?(h.host(), leaf, field, ""));
}

test "a node is not its own ancestor" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();

    const field = try h.declare("pong.field", c.KE_SCRIPT_REACH_ANY);
    const node = h.tree.create("Field", 0);
    var marker: u32 = 1;
    try testing.expect(h.host().bind.?(h.host(), node, field, &marker, null));

    try testing.expectEqual(@as(c.ke_entity, c.KE_ENTITY_INVALID), h.host().resolve_ancestor.?(h.host(), node, field, ""));
}
