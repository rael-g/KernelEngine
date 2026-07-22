// ke_scene_tree impl. Owns the cids of the framework's three scene-graph
// components (transform/hierarchy/name) registered against the caller-supplied
// ke_ecs. All hierarchy bookkeeping flows through ECS component reads/writes;
// there is no separate side state.

const std = @import("std");

const c = @import("c.zig").c;
const heap = @import("heap.zig");

const E = @import("kerror").Errors(c);

const mat4 = @import("mat4.zig");

/// Name capacity is dictated by the name component itself, so a deferred
/// create's inline copy can never truncate differently from the final write.
const name_max = @typeInfo(@FieldType(c.ke_name_component, "name")).array.len;

const State = struct {
    api: c.ke_scene_tree,
    ecs: *c.ke_ecs, // borrowed
    root: c.ke_entity,
    transform_cid: c.ke_component_id,
    hierarchy_cid: c.ke_component_id,
    name_cid: c.ke_component_id,
};

fn stateOf(self: *c.ke_scene_tree) *State {
    return @ptrCast(@alignCast(self.handle));
}

// -- helpers -----------------------------------------------------------------

fn getHierarchy(s: *State, e: c.ke_entity) ?*c.ke_hierarchy_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.hierarchy_cid)));
}

fn getName(s: *State, e: c.ke_entity) ?*const c.ke_name_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.name_cid)));
}

fn getTransform(s: *State, e: c.ke_entity) ?*c.ke_transform_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.transform_cid)));
}

/// Resolves an existing component cid by name, registering it when absent.
fn ensureComponent(ecs: *c.ke_ecs, name: [*c]const u8, size: usize) c.ke_component_id {
    var meta: c.ke_component_meta = undefined;
    if (ecs.component_lookup.?(ecs, name, &meta, null)) return meta.cid;
    return ecs.component_register.?(ecs, name, size);
}

/// Writes `src` into a fixed-size component name field, truncating to fit.
fn writeName(dst: []u8, src: [*c]const u8) void {
    if (src == null or src[0] == 0) {
        dst[0] = 0;
        return;
    }
    const text = std.mem.span(src);
    const n = @min(text.len, dst.len - 1);
    @memcpy(dst[0..n], text[0..n]);
    dst[n] = 0;
}

fn identityMatrix() c.ke_mat4 {
    var m: c.ke_mat4 = undefined;
    for (&m.m, 0..) |*cell, i| cell.* = if (i % 5 == 0) 1.0 else 0.0;
    return m;
}

// -- vtable: root ------------------------------------------------------------

fn vtRoot(self_in: ?*c.ke_scene_tree) callconv(.c) c.ke_entity {
    const self = self_in orelse return c.KE_ENTITY_INVALID;
    if (self.handle == null) return c.KE_ENTITY_INVALID;
    return stateOf(self).root;
}

// -- vtable: create_node -----------------------------------------------------

/// Attaches the three scene-graph components to an already-created (or
/// reserved) entity, populates them, and prepends it into the parent's child
/// list. Only valid where structural changes are legal: outside a wave, or at
/// the wave barrier via the deferred callback. Destroys the entity and returns
/// false if any component add fails.
fn populateNode(s: *State, entity: c.ke_entity, name: [*c]const u8, parent: c.ke_entity) bool {
    // Add all three components FIRST so the entity's archetype is stable. Each
    // component_add in flecs can move the entity to a new archetype and
    // invalidate any pointer captured from an earlier add — only once every add
    // is done can the field data be safely fetched and written.
    if (s.ecs.component_add.?(s.ecs, entity, s.transform_cid) == null or
        s.ecs.component_add.?(s.ecs, entity, s.hierarchy_cid) == null or
        s.ecs.component_add.?(s.ecs, entity, s.name_cid) == null)
    {
        s.ecs.entity_destroy.?(s.ecs, entity);
        return false;
    }

    if (getTransform(s, entity)) |t| {
        t.position = .{ .x = 0.0, .y = 0.0, .z = 0.0 };
        t.rotation = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 };
        t.scale = .{ .x = 1.0, .y = 1.0, .z = 1.0 };
        t.world_matrix = identityMatrix();
    }

    if (getHierarchy(s, entity)) |h| {
        h.parent = parent;
        h.first_child = c.KE_ENTITY_INVALID;
        h.next_sibling = c.KE_ENTITY_INVALID;
        h.prev_sibling = c.KE_ENTITY_INVALID;
    }

    if (@as(?*c.ke_name_component, @ptrCast(@alignCast(
        s.ecs.component_get.?(s.ecs, entity, s.name_cid),
    )))) |n| {
        writeName(&n.name, name);
    }

    // Prepend into the parent's child list (doubly linked, O(1)). Re-fetch the
    // hierarchy pointers: the writes above may have moved archetypes.
    const h = getHierarchy(s, entity);
    const ph = getHierarchy(s, parent);
    if (ph != null and h != null) {
        h.?.next_sibling = ph.?.first_child;
        if (ph.?.first_child != c.KE_ENTITY_INVALID) {
            if (getHierarchy(s, ph.?.first_child)) |sib| sib.prev_sibling = entity;
        }
        ph.?.first_child = entity;
    }
    return true;
}

// A reserved entity finalized at the wave barrier. Carries its own name copy so
// the payload stays self-contained after the arena copy.
const PendingCreate = extern struct {
    s: *State,
    entity: c.ke_entity,
    parent: c.ke_entity,
    name: [name_max]u8,
};

fn cbCreateNode(ecs: ?*c.ke_ecs, user: ?*anyopaque) callconv(.c) void {
    _ = ecs;
    const p: *PendingCreate = @ptrCast(@alignCast(user));
    _ = populateNode(p.s, p.entity, @ptrCast(&p.name), p.parent);
}

fn vtCreateNode(
    self_in: ?*c.ke_scene_tree,
    name: [*c]const u8,
    parent_in: c.ke_entity,
    ctx_in: ?*c.ke_system_ctx,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_entity {
    _ = out_error;
    const self = self_in orelse return c.KE_ENTITY_INVALID;
    if (self.handle == null) return c.KE_ENTITY_INVALID;
    const s = stateOf(self);
    const parent = if (parent_in == c.KE_ENTITY_INVALID) s.root else parent_in;

    // Inside a system body (ctx set) the world is mid-wave and structural
    // changes are illegal. Reserve a real id now (safe, atomic) and defer the
    // component adds + parent linking to the wave barrier, where they run
    // serially in registration order — so sibling links stay consistent even
    // across multiple creations under the same parent this tick.
    if (ctx_in) |ctx| {
        const entity = ctx.reserve.?(ctx);
        if (entity == c.KE_ENTITY_INVALID) return c.KE_ENTITY_INVALID;
        var pc: PendingCreate = .{
            .s = s,
            .entity = entity,
            .parent = parent,
            .name = undefined,
        };
        writeName(&pc.name, name);
        if (!ctx.@"defer".?(ctx, cbCreateNode, &pc, @sizeOf(PendingCreate)))
            return c.KE_ENTITY_INVALID;
        return entity;
    }

    // Immediate path (scene load, setup, tests): outside any wave.
    const entity = s.ecs.entity_create.?(s.ecs);
    if (entity == c.KE_ENTITY_INVALID) return c.KE_ENTITY_INVALID;
    if (!populateNode(s, entity, name, parent)) return c.KE_ENTITY_INVALID;
    return entity;
}

// -- vtable: find_node -------------------------------------------------------

fn nameEqualsSegment(name: ?*const c.ke_name_component, seg: []const u8) bool {
    const n = name orelse return false;
    const stored = std.mem.sliceTo(&n.name, 0);
    return std.mem.eql(u8, stored, seg);
}

fn findByName(s: *State, parent: c.ke_entity, target: []const u8) c.ke_entity {
    const h = getHierarchy(s, parent) orelse return c.KE_ENTITY_INVALID;
    var child = h.first_child;
    while (child != c.KE_ENTITY_INVALID) {
        if (nameEqualsSegment(getName(s, child), target)) return child;
        const found = findByName(s, child, target);
        if (found != c.KE_ENTITY_INVALID) return found;
        child = if (getHierarchy(s, child)) |ch| ch.next_sibling else c.KE_ENTITY_INVALID;
    }
    return c.KE_ENTITY_INVALID;
}

fn childBySegment(s: *State, parent: c.ke_entity, seg: []const u8) c.ke_entity {
    const h = getHierarchy(s, parent) orelse return c.KE_ENTITY_INVALID;
    var child = h.first_child;
    while (child != c.KE_ENTITY_INVALID) {
        if (nameEqualsSegment(getName(s, child), seg)) return child;
        child = if (getHierarchy(s, child)) |ch| ch.next_sibling else c.KE_ENTITY_INVALID;
    }
    return c.KE_ENTITY_INVALID;
}

fn vtFindNode(
    self_in: ?*c.ke_scene_tree,
    name_or_path: [*c]const u8,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_entity {
    _ = out_error;
    const self = self_in orelse return c.KE_ENTITY_INVALID;
    if (self.handle == null or name_or_path == null or name_or_path[0] == 0)
        return c.KE_ENTITY_INVALID;
    const s = stateOf(self);

    const path = std.mem.span(name_or_path);
    if (std.mem.indexOfScalar(u8, path, '/') == null) {
        return findByName(s, s.root, path);
    }

    // Leading "/" or "." are addressing noise: both mean "from the root".
    var rest = path;
    while (rest.len > 0 and (rest[0] == '/' or rest[0] == '.')) rest = rest[1..];

    var current = s.root;
    var it = std.mem.splitScalar(u8, rest, '/');
    while (it.next()) |seg| {
        if (current == c.KE_ENTITY_INVALID) break;
        if (seg.len == 0) continue;
        current = childBySegment(s, current, seg);
    }
    return current;
}

// -- vtable: destroy_node / destroy_all --------------------------------------

fn destroyEntitiesRecursive(s: *State, e: c.ke_entity) void {
    if (getHierarchy(s, e)) |h| {
        var child = h.first_child;
        while (child != c.KE_ENTITY_INVALID) {
            const next = if (getHierarchy(s, child)) |ch| ch.next_sibling else c.KE_ENTITY_INVALID;
            destroyEntitiesRecursive(s, child);
            child = next;
        }
    }
    s.ecs.entity_destroy.?(s.ecs, e);
}

/// Unlinks from the parent's child list, then destroys the subtree. The
/// structural part is legal only outside a wave or at the wave barrier.
fn destroySubtree(s: *State, entity: c.ke_entity) void {
    // Snapshot the navigation fields up front: the get_hierarchy calls below
    // (for parent and siblings) may move flecs archetypes and invalidate `h`.
    const h = getHierarchy(s, entity) orelse return;
    const h_prev = h.prev_sibling;
    const h_next = h.next_sibling;
    const h_parent = h.parent;

    if (h_parent != c.KE_ENTITY_INVALID) {
        if (getHierarchy(s, h_parent)) |ph| {
            if (ph.first_child == entity) ph.first_child = h_next;
        }
        if (h_prev != c.KE_ENTITY_INVALID) {
            if (getHierarchy(s, h_prev)) |prev| prev.next_sibling = h_next;
        }
        if (h_next != c.KE_ENTITY_INVALID) {
            if (getHierarchy(s, h_next)) |next| next.prev_sibling = h_prev;
        }
    }

    destroyEntitiesRecursive(s, entity);
}

const PendingDestroy = extern struct {
    s: *State,
    entity: c.ke_entity,
};

fn cbDestroyNode(ecs: ?*c.ke_ecs, user: ?*anyopaque) callconv(.c) void {
    _ = ecs;
    const p: *PendingDestroy = @ptrCast(@alignCast(user));
    destroySubtree(p.s, p.entity);
}

fn vtDestroyNode(
    self_in: ?*c.ke_scene_tree,
    entity: c.ke_entity,
    ctx_in: ?*c.ke_system_ctx,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null or entity == c.KE_ENTITY_INVALID) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const s = stateOf(self);

    if (getHierarchy(s, entity) == null) {
        E.fail(out_error, .not_found, "entity not found", @src());
        return false;
    }

    // Inside a system body entity_destroy is structural and illegal mid-wave;
    // defer the whole unlink + teardown to the wave barrier.
    if (ctx_in) |ctx| {
        var pd: PendingDestroy = .{ .s = s, .entity = entity };
        if (!ctx.@"defer".?(ctx, cbDestroyNode, &pd, @sizeOf(PendingDestroy))) {
            E.fail(out_error, .out_of_memory, "defer failed", @src());
            return false;
        }
        return true;
    }

    destroySubtree(s, entity);
    return true;
}

fn vtDestroyAll(self_in: ?*c.ke_scene_tree) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);

    // Destroy every child of root; root itself stays so the tree remains usable.
    const rh = getHierarchy(s, s.root) orelse return;
    var child = rh.first_child;
    while (child != c.KE_ENTITY_INVALID) {
        const next = if (getHierarchy(s, child)) |ch| ch.next_sibling else c.KE_ENTITY_INVALID;
        destroyEntitiesRecursive(s, child);
        child = next;
    }
    // Re-fetch: the destroys above may have moved the root's archetype.
    if (getHierarchy(s, s.root)) |h| h.first_child = c.KE_ENTITY_INVALID;
}

// -- vtable: propagate_transforms --------------------------------------------

fn propagateRecursive(s: *State, entity: c.ke_entity, parent_world: *const c.ke_mat4) void {
    var child_parent = parent_world;
    if (getTransform(s, entity)) |t| {
        var local: c.ke_mat4 = undefined;
        mat4.fromTransform(&local, &t.position, &t.rotation, &t.scale);
        mat4.mul(&t.world_matrix, &local, parent_world);
        child_parent = &t.world_matrix;
    }

    const h = getHierarchy(s, entity) orelse return;
    var child = h.first_child;
    while (child != c.KE_ENTITY_INVALID) {
        const next = if (getHierarchy(s, child)) |ch| ch.next_sibling else c.KE_ENTITY_INVALID;
        propagateRecursive(s, child, child_parent);
        child = next;
    }
}

fn vtPropagateTransforms(self_in: ?*c.ke_scene_tree) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    const identity = identityMatrix();
    const rh = getHierarchy(s, s.root) orelse return;
    var child = rh.first_child;
    while (child != c.KE_ENTITY_INVALID) {
        const next = if (getHierarchy(s, child)) |ch| ch.next_sibling else c.KE_ENTITY_INVALID;
        propagateRecursive(s, child, &identity);
        child = next;
    }
}

// -- teardown ----------------------------------------------------------------

fn vtDestroy(self_in: ?*c.ke_scene_tree) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    destroyEntitiesRecursive(s, s.root);
    heap.gpa.destroy(s);
}

// -- factory -----------------------------------------------------------------

export fn ke_scene_tree_create(
    ecs_in: ?*c.ke_ecs,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_scene_tree_handle {
    const null_handle = std.mem.zeroes(c.ke_scene_tree_handle);
    const ecs = ecs_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null_handle;
    };

    const s = heap.gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return null_handle;
    };
    s.* = .{
        .api = std.mem.zeroes(c.ke_scene_tree),
        .ecs = ecs,
        .root = c.KE_ENTITY_INVALID,
        .transform_cid = 0,
        .hierarchy_cid = 0,
        .name_cid = 0,
    };

    s.transform_cid = ensureComponent(ecs, c.KE_COMPONENT_NAME_TRANSFORM, @sizeOf(c.ke_transform_component));
    s.hierarchy_cid = ensureComponent(ecs, c.KE_COMPONENT_NAME_HIERARCHY, @sizeOf(c.ke_hierarchy_component));
    s.name_cid = ensureComponent(ecs, c.KE_COMPONENT_NAME_NAME, @sizeOf(c.ke_name_component));

    s.root = ecs.entity_create.?(ecs);
    if (s.root == c.KE_ENTITY_INVALID) {
        heap.gpa.destroy(s);
        E.fail(out_error, .general, "root entity creation failed", @src());
        return null_handle;
    }
    // Add all components FIRST, then fetch and populate: each add can move the
    // entity to a new archetype and invalidate pointers from earlier adds.
    if (ecs.component_add.?(ecs, s.root, s.hierarchy_cid) == null or
        ecs.component_add.?(ecs, s.root, s.name_cid) == null)
    {
        ecs.entity_destroy.?(ecs, s.root);
        heap.gpa.destroy(s);
        E.fail(out_error, .general, "root component setup failed", @src());
        return null_handle;
    }

    if (getHierarchy(s, s.root)) |h| {
        h.parent = c.KE_ENTITY_INVALID;
        h.first_child = c.KE_ENTITY_INVALID;
        h.next_sibling = c.KE_ENTITY_INVALID;
        h.prev_sibling = c.KE_ENTITY_INVALID;
    }
    if (@as(?*c.ke_name_component, @ptrCast(@alignCast(
        ecs.component_get.?(ecs, s.root, s.name_cid),
    )))) |n| {
        writeName(&n.name, "Root");
    }

    s.api.handle = s;
    s.api.root = vtRoot;
    s.api.create_node = vtCreateNode;
    s.api.destroy_node = vtDestroyNode;
    s.api.destroy_all = vtDestroyAll;
    s.api.find_node = vtFindNode;
    s.api.propagate_transforms = vtPropagateTransforms;

    return .{ .ref = &s.api, .destroy = vtDestroy };
}
