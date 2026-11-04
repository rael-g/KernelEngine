//! The scene tree: nodes as entities of the ecs, linked by the hierarchy component, with creation,
//! destruction, lookup and walking behind the scene tree vtable.

const abi_framework_components = @import("abi_framework_components");
const abi_spatial_contract = @import("abi_spatial_contract");
const abi_asset_resolver = @import("abi_asset_resolver");
const abi_scene_tree = @import("abi_scene_tree");
const std = @import("std");

const abi_ecs = @import("abi_ecs");
const abi_framework = @import("abi_framework");
const abi_framework_factory = @import("abi_framework_factory");
const abi_math = @import("abi_math");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const abi_spatial = @import("abi_spatial");
const heap = @import("heap");

const R = @import("result").Result(.{});
const log = std.log.scoped(.framework);

const mat4 = @import("mat4.zig");

/// Capacity of the name buffer of the name component; a stored name keeps one byte for its
/// terminator.
const name_max = @typeInfo(@FieldType(abi_framework_components.c.ke_name_component, "name")).array.len;

/// The state behind a tree handle, allocated by `ke_scene_tree_create` and freed by `vtDestroy`.
/// The tree stores no nodes of its own: a node is an entity of `ecs` carrying the hierarchy, name
/// and world transform components, and every question is answered from those components when it
/// is asked. The hierarchy component is an intrusive doubly linked list (parent, first and last
/// child, previous and next sibling), and a node's children are the chain from its first child.
/// `root` is the entity the invalid entity stands for as a parent. The ecs is borrowed;
/// `hierarchy` is owned and stays null unless the tree was created with a runtime.
/// `hierarchy_generation` moves with every link and unlink of a node.
const State = struct {
    api: abi_scene_tree.c.ke_scene_tree,
    ecs: *abi_ecs.c.ke_ecs,
    root: abi_asset_resolver.c.ke_entity,
    transform_cid: abi_asset_resolver.c.ke_component_id,
    transform2d_cid: abi_asset_resolver.c.ke_component_id,
    world_transform_cid: abi_asset_resolver.c.ke_component_id,
    hierarchy_cid: abi_asset_resolver.c.ke_component_id,
    name_cid: abi_asset_resolver.c.ke_component_id,
    hierarchy_generation: u64 = 0,
    hierarchy: abi_framework.c.ke_scene_hierarchy_handle,
};

fn stateOf(self: *abi_scene_tree.c.ke_scene_tree) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn getHierarchy(s: *State, e: abi_asset_resolver.c.ke_entity) ?*abi_framework_components.c.ke_hierarchy_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.hierarchy_cid)));
}

fn getName(s: *State, e: abi_asset_resolver.c.ke_entity) ?*const abi_framework_components.c.ke_name_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.name_cid)));
}

fn getTransform(s: *State, e: abi_asset_resolver.c.ke_entity) ?*abi_spatial.c.ke_transform_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.transform_cid)));
}

fn getTransform2d(s: *State, e: abi_asset_resolver.c.ke_entity) ?*const abi_spatial.c.ke_transform2d_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.transform2d_cid)));
}

fn getWorldTransform(s: *State, e: abi_asset_resolver.c.ke_entity) ?*abi_spatial.c.ke_world_transform_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.world_transform_cid)));
}

/// Registers a component the tree writes with the field table its header generates, or none when
/// no field of it is written by a scene. A component the ecs already knows keeps its id, so trees
/// created on one ecs share their ids, and its table is checked against the one registered first.
fn registerComponent(ecs: *abi_ecs.c.ke_ecs, name: [*c]const u8, comptime T: type, fields: []const abi_ecs.c.ke_component_field) R.Error!abi_asset_resolver.c.ke_component_id {
    var cid: abi_asset_resolver.c.ke_component_id = 0;
    try R.check(ecs.component_register.?(ecs, &abi_ecs.c.ke_component_params{ .name = name, .size = @sizeOf(T), .alignment = @alignOf(T), .fields = if (fields.len > 0) fields.ptr else null, .field_count = @intCast(fields.len) }, &cid));
    return cid;
}

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

fn identityMatrix() abi_math.c.ke_mat4 {
    var m: abi_math.c.ke_mat4 = undefined;
    for (&m.m, 0..) |*cell, i| cell.* = if (i % 5 == 0) 1.0 else 0.0;
    return m;
}

/// Slot `root`. Returns the root entity, or the invalid entity for a null tree.
fn vtRoot(self_in: ?*abi_scene_tree.c.ke_scene_tree) callconv(.c) abi_asset_resolver.c.ke_entity {
    const self = self_in orelse return abi_ecs.c.KE_ENTITY_INVALID;
    if (self.handle == null) return abi_ecs.c.KE_ENTITY_INVALID;
    return stateOf(self).root;
}

/// Slot `parent`. Returns the parent of the entity, or the invalid entity for the root, for an
/// entity without a hierarchy component and for a null tree.
fn vtParent(self_in: ?*abi_scene_tree.c.ke_scene_tree, entity: abi_asset_resolver.c.ke_entity) callconv(.c) abi_asset_resolver.c.ke_entity {
    const self = self_in orelse return abi_ecs.c.KE_ENTITY_INVALID;
    if (self.handle == null) return abi_ecs.c.KE_ENTITY_INVALID;
    const h = getHierarchy(stateOf(self), entity) orelse return abi_ecs.c.KE_ENTITY_INVALID;
    return h.parent;
}

/// Slot `first_child`. Returns the first child of the entity, or the invalid entity when it has
/// none, has no hierarchy component, or the tree is null.
fn vtFirstChild(self_in: ?*abi_scene_tree.c.ke_scene_tree, entity: abi_asset_resolver.c.ke_entity) callconv(.c) abi_asset_resolver.c.ke_entity {
    const self = self_in orelse return abi_ecs.c.KE_ENTITY_INVALID;
    if (self.handle == null) return abi_ecs.c.KE_ENTITY_INVALID;
    const h = getHierarchy(stateOf(self), entity) orelse return abi_ecs.c.KE_ENTITY_INVALID;
    return h.first_child;
}

fn listChildrenFirst(s: *State, parent: abi_asset_resolver.c.ke_entity, out: []abi_asset_resolver.c.ke_entity, count: *u32) void {
    const h = getHierarchy(s, parent) orelse return;
    var child = h.first_child;
    while (child != abi_ecs.c.KE_ENTITY_INVALID) {
        listChildrenFirst(s, child, out, count);
        if (count.* < out.len) out[count.*] = child;
        count.* += 1;
        child = if (getHierarchy(s, child)) |ch| ch.next_sibling else abi_ecs.c.KE_ENTITY_INVALID;
    }
}

/// Slot `children_first`. Walks the tree from the root depth-first, writing a node after its
/// subtree, and counts every node whether or not the buffer holds it. A null tree lists nothing.
fn vtChildrenFirst(self_in: ?*abi_scene_tree.c.ke_scene_tree, out_nodes: [*c]abi_asset_resolver.c.ke_entity, capacity: u32) callconv(.c) u32 {
    const self = self_in orelse return 0;
    if (self.handle == null) return 0;
    const s = stateOf(self);
    const out: []abi_asset_resolver.c.ke_entity = if (out_nodes == null) &.{} else out_nodes[0..capacity];
    var count: u32 = 0;
    listChildrenFirst(s, s.root, out, &count);
    return count;
}

/// Slot `next_sibling`. Returns the sibling created right after the entity under the same parent,
/// or the invalid entity when it is the last, has no hierarchy component, or the tree is null.
fn vtNextSibling(self_in: ?*abi_scene_tree.c.ke_scene_tree, entity: abi_asset_resolver.c.ke_entity) callconv(.c) abi_asset_resolver.c.ke_entity {
    const self = self_in orelse return abi_ecs.c.KE_ENTITY_INVALID;
    if (self.handle == null) return abi_ecs.c.KE_ENTITY_INVALID;
    const h = getHierarchy(stateOf(self), entity) orelse return abi_ecs.c.KE_ENTITY_INVALID;
    return h.next_sibling;
}

/// Called by both creation paths, so a node gets its components and links the same way whether it
/// is created at once or when the commands apply. The node is appended as the last child of the
/// parent, so children are visited in creation order; a parent without a hierarchy component
/// leaves the node unlinked. If one of the three components cannot be added, the entity is
/// destroyed and the ecs's failure comes back before anything is linked.
fn populateNode(s: *State, entity: abi_asset_resolver.c.ke_entity, name: [*c]const u8, parent: abi_asset_resolver.c.ke_entity) R.Error!void {
    errdefer _ = s.ecs.entity_destroy.?(s.ecs, entity);
    for ([_]abi_asset_resolver.c.ke_component_id{ s.world_transform_cid, s.hierarchy_cid, s.name_cid }) |cid| {
        var data: ?*anyopaque = null;
        try R.check(s.ecs.component_add.?(s.ecs, entity, cid, &data));
        if (data == null) return error.General;
    }

    if (getWorldTransform(s, entity)) |w| {
        w.matrix = identityMatrix();
    }

    if (getHierarchy(s, entity)) |h| {
        h.parent = parent;
        h.first_child = abi_ecs.c.KE_ENTITY_INVALID;
        h.last_child = abi_ecs.c.KE_ENTITY_INVALID;
        h.next_sibling = abi_ecs.c.KE_ENTITY_INVALID;
        h.prev_sibling = abi_ecs.c.KE_ENTITY_INVALID;
    }

    if (@as(?*abi_framework_components.c.ke_name_component, @ptrCast(@alignCast(
        s.ecs.component_get.?(s.ecs, entity, s.name_cid),
    )))) |n| {
        writeName(&n.name, name);
    }

    s.hierarchy_generation +%= 1;
    const h = getHierarchy(s, entity);
    const ph = getHierarchy(s, parent);
    if (ph != null and h != null) {
        h.?.prev_sibling = ph.?.last_child;
        if (ph.?.last_child != abi_ecs.c.KE_ENTITY_INVALID) {
            if (getHierarchy(s, ph.?.last_child)) |sib| sib.next_sibling = entity;
        } else {
            ph.?.first_child = entity;
        }
        ph.?.last_child = entity;
    }
}

/// Payload of a deferred create. The name is copied into it when the call is recorded, so the
/// caller's string is not read again when the commands apply.
const PendingCreate = extern struct {
    s: *State,
    entity: abi_asset_resolver.c.ke_entity,
    parent: abi_asset_resolver.c.ke_entity,
    name: [name_max]u8,
};

/// Runs when the commands apply. A node that populateNode cannot finish is destroyed, and the
/// failure is returned to the flush.
fn cbCreateNode(ecs: ?*abi_ecs.c.ke_ecs, user: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    _ = ecs;
    const p: *PendingCreate = @ptrCast(@alignCast(user));
    populateNode(p.s, p.entity, @ptrCast(&p.name), p.parent) catch |err| {
        log.warn("creating the recorded node {d} failed: {t}", .{ p.entity, err });
        return R.code(err);
    };
    return R.ok;
}

/// Slot `create_node`. Creates and links the node before returning; the invalid entity as parent
/// stands for the root. A null tree or out-parameter fails as an invalid argument, and an entity or
/// a component the ecs refuses fails as general, writing the invalid entity.
fn vtCreateNode(
    self_in: ?*abi_scene_tree.c.ke_scene_tree,
    name: [*c]const u8,
    parent_in: abi_asset_resolver.c.ke_entity,
    out_node: ?*abi_asset_resolver.c.ke_entity,
) callconv(.c) abi_result.c.ke_result {
    const out = out_node orelse return R.code(error.InvalidArgument);
    out.* = abi_ecs.c.KE_ENTITY_INVALID;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    const parent = if (parent_in == abi_ecs.c.KE_ENTITY_INVALID) s.root else parent_in;

    var entity: abi_asset_resolver.c.ke_entity = abi_ecs.c.KE_ENTITY_INVALID;
    const created = s.ecs.entity_create.?(s.ecs, &entity);
    if (created != abi_result.c.KE_OK) return created;
    populateNode(s, entity, name, parent) catch |err| return R.code(err);
    out.* = entity;
    return R.ok;
}

/// Slot `create_node_deferred`. The id is reserved before returning and is usable as a reference
/// at once; the node gets its components and its link when the commands apply, so a failure of
/// that recorded call fails the flush that applies it. A null tree, command queue or out-parameter fails as an
/// invalid argument, and a failed reservation or recording with the queue's code; each writes the
/// invalid entity.
fn vtCreateNodeDeferred(
    self_in: ?*abi_scene_tree.c.ke_scene_tree,
    name: [*c]const u8,
    parent_in: abi_asset_resolver.c.ke_entity,
    commands: ?*abi_ecs.c.ke_ecs_commands,
    out_node: ?*abi_asset_resolver.c.ke_entity,
) callconv(.c) abi_result.c.ke_result {
    const out = out_node orelse return R.code(error.InvalidArgument);
    out.* = abi_ecs.c.KE_ENTITY_INVALID;
    const self = self_in orelse return R.code(error.InvalidArgument);
    const cmds = commands orelse return R.code(error.InvalidArgument);
    if (self.handle == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    const parent = if (parent_in == abi_ecs.c.KE_ENTITY_INVALID) s.root else parent_in;

    var entity: abi_asset_resolver.c.ke_entity = abi_ecs.c.KE_ENTITY_INVALID;
    const spawned = cmds.spawn.?(cmds, &entity);
    if (spawned != abi_result.c.KE_OK) return spawned;
    var pc: PendingCreate = .{
        .s = s,
        .entity = entity,
        .parent = parent,
        .name = undefined,
    };
    writeName(&pc.name, name);
    const recorded = cmds.@"defer".?(cmds, cbCreateNode, &pc, @sizeOf(PendingCreate));
    if (recorded != abi_result.c.KE_OK) return recorded;
    out.* = entity;
    return R.ok;
}

/// Compares against the stored name, which may be a cut-short copy of the name the node was made
/// with.
fn nameEqualsSegment(name: ?*const abi_framework_components.c.ke_name_component, seg: []const u8) bool {
    const n = name orelse return false;
    const stored = std.mem.sliceTo(&n.name, 0);
    return std.mem.eql(u8, stored, seg);
}

/// The name search of `vtFindNode`. The parent's own name is never compared, only its descendants'.
fn findByName(s: *State, parent: abi_asset_resolver.c.ke_entity, target: []const u8) abi_asset_resolver.c.ke_entity {
    const h = getHierarchy(s, parent) orelse return abi_ecs.c.KE_ENTITY_INVALID;
    var child = h.first_child;
    while (child != abi_ecs.c.KE_ENTITY_INVALID) {
        if (nameEqualsSegment(getName(s, child), target)) return child;
        const found = findByName(s, child, target);
        if (found != abi_ecs.c.KE_ENTITY_INVALID) return found;
        child = if (getHierarchy(s, child)) |ch| ch.next_sibling else abi_ecs.c.KE_ENTITY_INVALID;
    }
    return abi_ecs.c.KE_ENTITY_INVALID;
}

fn childBySegment(s: *State, parent: abi_asset_resolver.c.ke_entity, seg: []const u8) abi_asset_resolver.c.ke_entity {
    const h = getHierarchy(s, parent) orelse return abi_ecs.c.KE_ENTITY_INVALID;
    var child = h.first_child;
    while (child != abi_ecs.c.KE_ENTITY_INVALID) {
        if (nameEqualsSegment(getName(s, child), seg)) return child;
        child = if (getHierarchy(s, child)) |ch| ch.next_sibling else abi_ecs.c.KE_ENTITY_INVALID;
    }
    return abi_ecs.c.KE_ENTITY_INVALID;
}

/// Slot `find_node`. A string without a slash goes to `findByName`, which returns the first match
/// in depth-first child order; one with a slash is walked segment by segment from the root,
/// ignoring leading dots and slashes and empty segments. An empty or null string, or a name that
/// matches nothing, returns the invalid entity.
fn vtFindNode(
    self_in: ?*abi_scene_tree.c.ke_scene_tree,
    name_or_path: [*c]const u8,
) callconv(.c) abi_asset_resolver.c.ke_entity {
    const self = self_in orelse return abi_ecs.c.KE_ENTITY_INVALID;
    if (self.handle == null or name_or_path == null or name_or_path[0] == 0)
        return abi_ecs.c.KE_ENTITY_INVALID;
    const s = stateOf(self);

    const path = std.mem.span(name_or_path);
    if (std.mem.indexOfScalar(u8, path, '/') == null) {
        return findByName(s, s.root, path);
    }

    var rest = path;
    while (rest.len > 0 and (rest[0] == '/' or rest[0] == '.')) rest = rest[1..];

    var current = s.root;
    var it = std.mem.splitScalar(u8, rest, '/');
    while (it.next()) |seg| {
        if (current == abi_ecs.c.KE_ENTITY_INVALID) break;
        if (seg.len == 0) continue;
        current = childBySegment(s, current, seg);
    }
    return current;
}

/// Destroys the entity and its subtree, children first. A destroy the ecs refuses does not stop
/// the others; the first refusal is returned once all were tried.
fn destroyEntitiesRecursive(s: *State, e: abi_asset_resolver.c.ke_entity) R.Error!void {
    var first: R.Error!void = {};
    if (getHierarchy(s, e)) |h| {
        var child = h.first_child;
        while (child != abi_ecs.c.KE_ENTITY_INVALID) {
            const next = if (getHierarchy(s, child)) |ch| ch.next_sibling else abi_ecs.c.KE_ENTITY_INVALID;
            destroyEntitiesRecursive(s, child) catch |err| {
                if (first) |_| first = err else |_| {}
            };
            child = next;
        }
    }
    R.check(s.ecs.entity_destroy.?(s.ecs, e)) catch |err| {
        if (first) |_| first = err else |_| {}
    };
    return first;
}

/// Unlinks the entity from its neighbours and its parent, then destroys its subtree. The recorded
/// destroy calls it when the commands apply, and an entity already gone by then has no hierarchy
/// component, so it is skipped.
fn destroySubtree(s: *State, entity: abi_asset_resolver.c.ke_entity) R.Error!void {
    const h = getHierarchy(s, entity) orelse return;
    const h_prev = h.prev_sibling;
    const h_next = h.next_sibling;
    const h_parent = h.parent;
    s.hierarchy_generation +%= 1;

    if (h_parent != abi_ecs.c.KE_ENTITY_INVALID) {
        if (getHierarchy(s, h_parent)) |ph| {
            if (ph.first_child == entity) ph.first_child = h_next;
            if (ph.last_child == entity) ph.last_child = h_prev;
        }
        if (h_prev != abi_ecs.c.KE_ENTITY_INVALID) {
            if (getHierarchy(s, h_prev)) |prev| prev.next_sibling = h_next;
        }
        if (h_next != abi_ecs.c.KE_ENTITY_INVALID) {
            if (getHierarchy(s, h_next)) |next| next.prev_sibling = h_prev;
        }
    }

    try destroyEntitiesRecursive(s, entity);
}

/// Payload of a deferred destroy, read by `cbDestroyNode` when the commands apply.
const PendingDestroy = extern struct {
    s: *State,
    entity: abi_asset_resolver.c.ke_entity,
};

/// Runs when the commands apply, and does not repeat the checks made when the call was recorded.
fn cbDestroyNode(ecs: ?*abi_ecs.c.ke_ecs, user: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    _ = ecs;
    const p: *PendingDestroy = @ptrCast(@alignCast(user));
    destroySubtree(p.s, p.entity) catch |err| {
        log.warn("destroying the recorded node {d} failed: {t}", .{ p.entity, err });
        return R.code(err);
    };
    return R.ok;
}

/// Shared by the immediate and the deferred destroy. Fails as an invalid argument for a null tree,
/// a null handle or an invalid entity, and as not found for an entity that has no hierarchy
/// component.
fn checkDestroyable(self_in: ?*abi_scene_tree.c.ke_scene_tree, entity: abi_asset_resolver.c.ke_entity) R.Error!*State {
    const self = self_in orelse return error.InvalidArgument;
    if (self.handle == null or entity == abi_ecs.c.KE_ENTITY_INVALID) return error.InvalidArgument;
    const s = stateOf(self);
    if (getHierarchy(s, entity) == null) return error.NotFound;
    return s;
}

/// Slot `destroy_node`. Unlinks the entity and destroys it with its whole subtree, children
/// first. Fails as `checkDestroyable` does.
fn vtDestroyNode(
    self_in: ?*abi_scene_tree.c.ke_scene_tree,
    entity: abi_asset_resolver.c.ke_entity,
) callconv(.c) abi_result.c.ke_result {
    const s = checkDestroyable(self_in, entity) catch |err| return R.code(err);
    return R.of(destroySubtree(s, entity));
}

/// Slot `destroy_node_deferred`. Checks the entity now and records the unlink and destroy, which
/// happen only when the commands apply. A null command queue is reported before the entity is
/// checked; the other failures are those of `vtDestroyNode`, plus the queue's code when recording
/// fails.
fn vtDestroyNodeDeferred(
    self_in: ?*abi_scene_tree.c.ke_scene_tree,
    entity: abi_asset_resolver.c.ke_entity,
    commands: ?*abi_ecs.c.ke_ecs_commands,
) callconv(.c) abi_result.c.ke_result {
    const cmds = commands orelse return R.code(error.InvalidArgument);
    const s = checkDestroyable(self_in, entity) catch |err| return R.code(err);
    var pd: PendingDestroy = .{ .s = s, .entity = entity };
    return cmds.@"defer".?(cmds, cbDestroyNode, &pd, @sizeOf(PendingDestroy));
}

/// Slot `destroy_all`. Destroys the root's children without unlinking each one from its
/// neighbours; the root's first and last child fields are cleared once at the end. The root
/// entity stays. A subtree the ecs refuses does not stop the rest; the first failure is returned.
/// A null tree or handle fails as an invalid argument, a root without hierarchy as not found.
fn vtDestroyAll(self_in: ?*abi_scene_tree.c.ke_scene_tree) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);

    const rh = getHierarchy(s, s.root) orelse return R.code(error.NotFound);
    s.hierarchy_generation +%= 1;
    var first_failure: abi_result.c.ke_result = R.ok;
    var child = rh.first_child;
    while (child != abi_ecs.c.KE_ENTITY_INVALID) {
        const next = if (getHierarchy(s, child)) |ch| ch.next_sibling else abi_ecs.c.KE_ENTITY_INVALID;
        destroyEntitiesRecursive(s, child) catch |err| {
            log.warn("destroying the subtree of node {d} failed: {t}", .{ child, err });
            if (first_failure == R.ok) first_failure = R.code(err);
        };
        child = next;
    }
    if (getHierarchy(s, s.root)) |h| {
        h.first_child = abi_ecs.c.KE_ENTITY_INVALID;
        h.last_child = abi_ecs.c.KE_ENTITY_INVALID;
    }
    return first_failure;
}

/// An entity without a world transform stores no matrix, so its children are composed with the
/// matrix of its nearest ancestor that has one.
fn propagateRecursive(s: *State, entity: abi_asset_resolver.c.ke_entity, parent_world: *const abi_math.c.ke_mat4) void {
    var child_parent = parent_world;
    if (getWorldTransform(s, entity)) |w| {
        var local = identityMatrix();
        if (getTransform(s, entity)) |t| {
            mat4.fromTransform(&local, &t.position, &t.rotation, &t.scale);
        } else if (getTransform2d(s, entity)) |t2| {
            mat4.fromTransform2d(&local, &t2.position, t2.rotation, &t2.scale, t2.depth);
        }
        mat4.mul(&w.matrix, &local, parent_world);
        child_parent = &w.matrix;
    }

    const h = getHierarchy(s, entity) orelse return;
    var child = h.first_child;
    while (child != abi_ecs.c.KE_ENTITY_INVALID) {
        const next = if (getHierarchy(s, child)) |ch| ch.next_sibling else abi_ecs.c.KE_ENTITY_INVALID;
        propagateRecursive(s, child, child_parent);
        child = next;
    }
}

/// Slot `propagate_transforms`. Refreshes every world matrix under the root now, recursively. The
/// root has no world transform, so the walk starts from the identity matrix at its children.
/// Slot `hierarchy_generation`. Returns the count `populateNode`, `destroySubtree` and
/// `vtDestroyAll` move, or 0 for a null tree.
fn vtHierarchyGeneration(self_in: ?*abi_scene_tree.c.ke_scene_tree) callconv(.c) u64 {
    const self = self_in orelse return 0;
    if (self.handle == null) return 0;
    return stateOf(self).hierarchy_generation;
}

fn vtPropagateTransforms(self_in: ?*abi_scene_tree.c.ke_scene_tree) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    const identity = identityMatrix();
    const rh = getHierarchy(s, s.root) orelse return;
    s.hierarchy_generation +%= 1;
    var child = rh.first_child;
    while (child != abi_ecs.c.KE_ENTITY_INVALID) {
        const next = if (getHierarchy(s, child)) |ch| ch.next_sibling else abi_ecs.c.KE_ENTITY_INVALID;
        propagateRecursive(s, child, &identity);
        child = next;
    }
}

/// The handle's destroy. Releases the scene hierarchy first. After it returns the State, the root
/// and every node under it are gone; the ecs itself is not destroyed.
fn vtDestroy(self_in: ?*abi_scene_tree.c.ke_scene_tree) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    if (s.hierarchy.destroy) |d| d(s.hierarchy.ref);
    destroyEntitiesRecursive(s, s.root) catch |err|
        log.warn("destroying the tree's entities failed: {t}", .{err});
    heap.gpa.destroy(s);
}

/// Factory. On success the handle's ref is the vtable inside a new State: the five components are
/// registered on the ecs when it does not know them, and a root entity named "Root" carries
/// hierarchy and name. A runtime additionally creates the scene hierarchy the tree owns. A null
/// ecs or out-parameter fails as an invalid argument, a failed allocation as out of memory, a
/// refused component or hierarchy with the code of the ecs or the runtime, and a failed root entity
/// or root component as general. Each leaves the handle zeroed and releases whatever this call
/// created, so no entity or allocation is left.
export fn ke_scene_tree_create(
    ecs_in: ?*abi_ecs.c.ke_ecs,
    runtime: ?*abi_runtime.c.ke_runtime,
    out_tree: ?*abi_scene_tree.c.ke_scene_tree_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_tree orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_scene_tree.c.ke_scene_tree_handle);
    const ecs = ecs_in orelse return R.code(error.InvalidArgument);
    out.* = create(ecs, runtime) catch |err| return R.code(err);
    return R.ok;
}

fn create(ecs: *abi_ecs.c.ke_ecs, runtime: ?*abi_runtime.c.ke_runtime) R.Error!abi_scene_tree.c.ke_scene_tree_handle {
    const s = try heap.gpa.create(State);
    errdefer heap.gpa.destroy(s);
    s.* = .{
        .api = std.mem.zeroes(abi_scene_tree.c.ke_scene_tree),
        .ecs = ecs,
        .root = abi_ecs.c.KE_ENTITY_INVALID,
        .transform_cid = try registerComponent(ecs, abi_spatial_contract.c.KE_COMPONENT_NAME_TRANSFORM, abi_spatial.c.ke_transform_component, &abi_spatial_contract.c.ke_transform_component_fields),
        .transform2d_cid = try registerComponent(ecs, abi_spatial_contract.c.KE_COMPONENT_NAME_TRANSFORM2D, abi_spatial.c.ke_transform2d_component, &abi_spatial_contract.c.ke_transform2d_component_fields),
        .world_transform_cid = try registerComponent(ecs, abi_spatial_contract.c.KE_COMPONENT_NAME_WORLD_TRANSFORM, abi_spatial.c.ke_world_transform_component, &.{}),
        .hierarchy_cid = try registerComponent(ecs, abi_framework_components.c.KE_COMPONENT_NAME_HIERARCHY, abi_framework_components.c.ke_hierarchy_component, &.{}),
        .name_cid = try registerComponent(ecs, abi_framework_components.c.KE_COMPONENT_NAME_NAME, abi_framework_components.c.ke_name_component, &.{}),
        .hierarchy = std.mem.zeroes(abi_framework.c.ke_scene_hierarchy_handle),
    };

    try R.check(ecs.entity_create.?(ecs, &s.root));
    errdefer _ = ecs.entity_destroy.?(ecs, s.root);
    for ([_]abi_asset_resolver.c.ke_component_id{ s.hierarchy_cid, s.name_cid }) |cid| {
        var data: ?*anyopaque = null;
        try R.check(ecs.component_add.?(ecs, s.root, cid, &data));
        if (data == null) return error.General;
    }

    if (getHierarchy(s, s.root)) |h| {
        h.parent = abi_ecs.c.KE_ENTITY_INVALID;
        h.first_child = abi_ecs.c.KE_ENTITY_INVALID;
        h.last_child = abi_ecs.c.KE_ENTITY_INVALID;
        h.next_sibling = abi_ecs.c.KE_ENTITY_INVALID;
        h.prev_sibling = abi_ecs.c.KE_ENTITY_INVALID;
    }
    if (@as(?*abi_framework_components.c.ke_name_component, @ptrCast(@alignCast(
        ecs.component_get.?(ecs, s.root, s.name_cid),
    )))) |n| {
        writeName(&n.name, "Root");
    }

    s.api.handle = s;
    s.api.root = vtRoot;
    s.api.create_node = vtCreateNode;
    s.api.create_node_deferred = vtCreateNodeDeferred;
    s.api.destroy_node = vtDestroyNode;
    s.api.destroy_node_deferred = vtDestroyNodeDeferred;
    s.api.destroy_all = vtDestroyAll;
    s.api.find_node = vtFindNode;
    s.api.parent = vtParent;
    s.api.first_child = vtFirstChild;
    s.api.next_sibling = vtNextSibling;
    s.api.children_first = vtChildrenFirst;
    s.api.propagate_transforms = vtPropagateTransforms;
    s.api.hierarchy_generation = vtHierarchyGeneration;

    if (runtime) |rt| try R.check(abi_framework_factory.c.ke_scene_hierarchy_create(rt, ecs, &s.hierarchy));

    return .{ .ref = &s.api, .destroy = vtDestroy };
}

const testing = std.testing;

const matrix_tolerance: f32 = 1e-5;

const fake_max_components = 16;
const fake_max_entities = 128;

const FakeComponent = struct {
    name: []const u8,
    size: usize,
    fields: [*c]const abi_ecs.c.ke_component_field,
};

pub const FakeEcs = struct {
    vtable: abi_ecs.c.ke_ecs,
    arena: std.heap.ArenaAllocator,
    components: [fake_max_components]FakeComponent,
    component_count: usize,
    alive: [fake_max_entities]bool,
    storage: [fake_max_entities][fake_max_components]?[*]u8,
    next_entity: abi_asset_resolver.c.ke_entity,
    refused: ?[]const u8,
};

fn fakeEcsOf(self: ?*abi_ecs.c.ke_ecs) *FakeEcs {
    return @ptrCast(@alignCast(self.?.handle));
}

fn fakeSlot(f: *FakeEcs, entity: abi_asset_resolver.c.ke_entity, cid: abi_asset_resolver.c.ke_component_id) ?*?[*]u8 {
    if (entity == abi_ecs.c.KE_ENTITY_INVALID or entity > fake_max_entities) return null;
    const row = entity - 1;
    if (!f.alive[row]) return null;
    if (cid == 0 or cid > f.component_count) return null;
    return &f.storage[row][cid - 1];
}

fn fakeEntityCreate(self: ?*abi_ecs.c.ke_ecs, out_entity: [*c]abi_asset_resolver.c.ke_entity) callconv(.c) abi_result.c.ke_result {
    const f = fakeEcsOf(self);
    out_entity.* = abi_ecs.c.KE_ENTITY_INVALID;
    if (f.next_entity >= fake_max_entities) return R.code(error.OutOfMemory);
    f.next_entity += 1;
    f.alive[f.next_entity - 1] = true;
    out_entity.* = f.next_entity;
    return R.ok;
}

fn fakeEntityReserve(self: ?*abi_ecs.c.ke_ecs, out_entity: [*c]abi_asset_resolver.c.ke_entity) callconv(.c) abi_result.c.ke_result {
    return fakeEntityCreate(self, out_entity);
}

fn fakeEntityDestroy(self: ?*abi_ecs.c.ke_ecs, entity: abi_asset_resolver.c.ke_entity) callconv(.c) abi_result.c.ke_result {
    const f = fakeEcsOf(self);
    if (entity == abi_ecs.c.KE_ENTITY_INVALID or entity > fake_max_entities) return R.code(error.InvalidArgument);
    const row = entity - 1;
    f.alive[row] = false;
    for (&f.storage[row]) |*cell| cell.* = null;
    return R.ok;
}

fn fakeComponentRegister(
    self: ?*abi_ecs.c.ke_ecs,
    params: [*c]const abi_ecs.c.ke_component_params,
    out_cid: [*c]abi_asset_resolver.c.ke_component_id,
) callconv(.c) abi_result.c.ke_result {
    const f = fakeEcsOf(self);
    const wanted = std.mem.span(params.*.name.?);
    if (f.refused) |r| if (std.mem.eql(u8, r, wanted)) {
        return answer(out_cid, 0);
    };
    for (f.components[0..f.component_count], 0..) |comp, i| {
        if (std.mem.eql(u8, comp.name, wanted)) return answer(out_cid, @intCast(i + 1));
    }
    if (f.component_count >= fake_max_components) return answer(out_cid, 0);
    const name = f.arena.allocator().dupe(u8, wanted) catch return answer(out_cid, 0);
    f.components[f.component_count] = .{ .name = name, .size = params.*.size, .fields = params.*.fields };
    f.component_count += 1;
    return answer(out_cid, @intCast(f.component_count));
}

fn answer(out_cid: [*c]abi_asset_resolver.c.ke_component_id, cid: abi_asset_resolver.c.ke_component_id) abi_result.c.ke_result {
    out_cid.* = cid;
    return if (cid == 0) R.code(error.InvalidArgument) else R.ok;
}

fn fakeComponentLookup(
    self: ?*abi_ecs.c.ke_ecs,
    name: [*c]const u8,
    out_meta: [*c]abi_ecs.c.ke_component_meta,
) callconv(.c) bool {
    const f = fakeEcsOf(self);
    const wanted = std.mem.span(name);
    for (f.components[0..f.component_count], 0..) |comp, i| {
        if (!std.mem.eql(u8, comp.name, wanted)) continue;
        if (out_meta != null) {
            out_meta.* = .{
                .cid = @intCast(i + 1),
                .size = comp.size,
                .fields = null,
                .field_count = 0,
            };
        }
        return true;
    }
    return false;
}

fn fakeComponentAdd(
    self: ?*abi_ecs.c.ke_ecs,
    entity: abi_asset_resolver.c.ke_entity,
    component: abi_asset_resolver.c.ke_component_id,
    out_data: [*c]?*anyopaque,
) callconv(.c) abi_result.c.ke_result {
    const f = fakeEcsOf(self);
    out_data.* = null;
    const slot = fakeSlot(f, entity, component) orelse return R.code(error.InvalidArgument);
    if (slot.*) |existing| {
        out_data.* = existing;
        return R.ok;
    }
    const size = f.components[component - 1].size;
    const block = f.arena.allocator().alignedAlloc(u8, .of(u64), @max(size, 1)) catch return R.code(error.OutOfMemory);
    @memset(block, 0);
    slot.* = block.ptr;
    out_data.* = block.ptr;
    return R.ok;
}

fn fakeComponentRemove(
    self: ?*abi_ecs.c.ke_ecs,
    entity: abi_asset_resolver.c.ke_entity,
    component: abi_asset_resolver.c.ke_component_id,
) callconv(.c) abi_result.c.ke_result {
    const f = fakeEcsOf(self);
    const slot = fakeSlot(f, entity, component) orelse return R.code(error.InvalidArgument);
    slot.* = null;
    return R.ok;
}

fn fakeComponentGet(
    self: ?*abi_ecs.c.ke_ecs,
    entity: abi_asset_resolver.c.ke_entity,
    component: abi_asset_resolver.c.ke_component_id,
) callconv(.c) ?*anyopaque {
    const f = fakeEcsOf(self);
    const slot = fakeSlot(f, entity, component) orelse return null;
    return slot.*;
}

fn fakeComponentSize(self: ?*abi_ecs.c.ke_ecs, cid: abi_asset_resolver.c.ke_component_id) callconv(.c) usize {
    const f = fakeEcsOf(self);
    if (cid == 0 or cid > f.component_count) return 0;
    return f.components[cid - 1].size;
}

pub const Fixture = struct {
    ecs: FakeEcs,
    handle: abi_scene_tree.c.ke_scene_tree_handle,

    pub fn init(self: *Fixture) !void {
        self.ecs.arena = std.heap.ArenaAllocator.init(testing.allocator);
        self.ecs.component_count = 0;
        self.ecs.next_entity = 0;
        self.ecs.refused = null;
        @memset(&self.ecs.alive, false);
        for (&self.ecs.storage) |*row| @memset(row, null);
        self.ecs.vtable = std.mem.zeroes(abi_ecs.c.ke_ecs);
        self.ecs.vtable.handle = &self.ecs;
        self.ecs.vtable.entity_create = fakeEntityCreate;
        self.ecs.vtable.entity_reserve = fakeEntityReserve;
        self.ecs.vtable.entity_destroy = fakeEntityDestroy;
        self.ecs.vtable.component_register = fakeComponentRegister;
        self.ecs.vtable.component_lookup = fakeComponentLookup;
        self.ecs.vtable.component_add = fakeComponentAdd;
        self.ecs.vtable.component_remove = fakeComponentRemove;
        self.ecs.vtable.component_get = fakeComponentGet;
        self.ecs.vtable.component_size = fakeComponentSize;

        try testing.expectEqual(R.ok, ke_scene_tree_create(&self.ecs.vtable, null, &self.handle));
        try testing.expect(self.handle.ref != null);
    }

    pub fn deinit(self: *Fixture) void {
        if (self.handle.destroy) |d| d(self.handle.ref);
        self.ecs.arena.deinit();
    }

    pub fn tree(self: *Fixture) [*c]abi_scene_tree.c.ke_scene_tree {
        return self.handle.ref;
    }

    pub fn create(self: *Fixture, name: [*c]const u8, parent: abi_asset_resolver.c.ke_entity) abi_asset_resolver.c.ke_entity {
        const t = self.tree();
        var node: abi_asset_resolver.c.ke_entity = abi_ecs.c.KE_ENTITY_INVALID;
        _ = t.*.create_node.?(t, name, parent, &node);
        return node;
    }

    fn find(self: *Fixture, path: [*c]const u8) abi_asset_resolver.c.ke_entity {
        const t = self.tree();
        return t.*.find_node.?(t, path);
    }

    fn hierarchyOf(self: *Fixture, e: abi_asset_resolver.c.ke_entity) ?*abi_framework_components.c.ke_hierarchy_component {
        var meta: abi_ecs.c.ke_component_meta = undefined;
        if (!fakeComponentLookup(&self.ecs.vtable, abi_framework_components.c.KE_COMPONENT_NAME_HIERARCHY, &meta)) return null;
        return @ptrCast(@alignCast(fakeComponentGet(&self.ecs.vtable, e, meta.cid)));
    }

    fn transformOf(self: *Fixture, e: abi_asset_resolver.c.ke_entity) ?*abi_spatial.c.ke_transform_component {
        var meta: abi_ecs.c.ke_component_meta = undefined;
        if (!fakeComponentLookup(&self.ecs.vtable, abi_spatial_contract.c.KE_COMPONENT_NAME_TRANSFORM, &meta)) return null;
        if (fakeComponentGet(&self.ecs.vtable, e, meta.cid)) |existing| {
            return @ptrCast(@alignCast(existing));
        }
        var data: ?*anyopaque = null;
        if (fakeComponentAdd(&self.ecs.vtable, e, meta.cid, &data) != R.ok) return null;
        const added: ?*abi_spatial.c.ke_transform_component = @ptrCast(@alignCast(data));
        if (added) |t| {
            t.position = .{ .x = 0, .y = 0, .z = 0 };
            t.rotation = .{ .x = 0, .y = 0, .z = 0, .w = 1 };
            t.scale = .{ .x = 1, .y = 1, .z = 1 };
        }
        return added;
    }

    fn worldOf(self: *Fixture, e: abi_asset_resolver.c.ke_entity) ?*abi_spatial.c.ke_world_transform_component {
        var meta: abi_ecs.c.ke_component_meta = undefined;
        if (!fakeComponentLookup(&self.ecs.vtable, abi_spatial_contract.c.KE_COMPONENT_NAME_WORLD_TRANSFORM, &meta)) return null;
        return @ptrCast(@alignCast(fakeComponentGet(&self.ecs.vtable, e, meta.cid)));
    }
};

test "a fresh tree has one stable root" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const t = f.tree();
    const r = t.*.root.?(t);
    try testing.expect(r != abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expectEqual(r, t.*.root.?(t));
}

test "a node created without a parent lands under the root" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const child = f.create("X", abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expect(child != abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expectEqual(child, f.find("X"));
}

test "a node created with an explicit parent is reachable through it" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const parent = f.create("Parent", abi_ecs.c.KE_ENTITY_INVALID);
    const child = f.create("Child", parent);
    try testing.expect(child != abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expectEqual(child, f.find("Parent/Child"));
}

test "every sibling under one parent stays reachable and points back at it" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const parent = f.create("P", abi_ecs.c.KE_ENTITY_INVALID);
    const a = f.create("A", parent);
    const b = f.create("B", parent);
    const d = f.create("C", parent);
    try testing.expect(a != abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expect(b != abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expect(d != abi_ecs.c.KE_ENTITY_INVALID);

    try testing.expectEqual(a, f.find("P/A"));
    try testing.expectEqual(b, f.find("P/B"));
    try testing.expectEqual(d, f.find("P/C"));

    const ph = f.hierarchyOf(parent) orelse return error.MissingHierarchy;
    var walked: usize = 0;
    var cur = ph.first_child;
    while (cur != abi_ecs.c.KE_ENTITY_INVALID and walked < fake_max_entities) : (walked += 1) {
        const ch = f.hierarchyOf(cur) orelse return error.MissingHierarchy;
        try testing.expectEqual(parent, ch.parent);
        cur = ch.next_sibling;
    }
    try testing.expectEqual(@as(usize, 3), walked);
}

test "siblings link in the order they were created" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const parent = f.create("P", abi_ecs.c.KE_ENTITY_INVALID);
    const a = f.create("A", parent);
    const b = f.create("B", parent);
    const d = f.create("C", parent);

    const ph = f.hierarchyOf(parent) orelse return error.MissingHierarchy;
    var order: [3]abi_asset_resolver.c.ke_entity = .{ 0, 0, 0 };
    var walked: usize = 0;
    var cur = ph.first_child;
    while (cur != abi_ecs.c.KE_ENTITY_INVALID and walked < order.len) : (walked += 1) {
        order[walked] = cur;
        const ch = f.hierarchyOf(cur) orelse return error.MissingHierarchy;
        cur = ch.next_sibling;
    }
    try testing.expectEqual(a, order[0]);
    try testing.expectEqual(b, order[1]);
    try testing.expectEqual(d, order[2]);
    try testing.expectEqual(d, ph.last_child);
}

test "the tree walks a child list without anyone reading the hierarchy component" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const tree: *abi_scene_tree.c.ke_scene_tree = @ptrCast(f.handle.ref);
    const parent = f.create("P", abi_ecs.c.KE_ENTITY_INVALID);
    const a = f.create("A", parent);
    const b = f.create("B", parent);
    const d = f.create("C", parent);

    var order: [3]abi_asset_resolver.c.ke_entity = .{ 0, 0, 0 };
    var walked: usize = 0;
    var cur = tree.first_child.?(tree, parent);
    while (cur != abi_ecs.c.KE_ENTITY_INVALID and walked < order.len) : (walked += 1) {
        order[walked] = cur;
        cur = tree.next_sibling.?(tree, cur);
    }

    try testing.expectEqual(@as(usize, 3), walked);
    try testing.expectEqual(a, order[0]);
    try testing.expectEqual(b, order[1]);
    try testing.expectEqual(d, order[2]);
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, tree.next_sibling.?(tree, d));
}

test "a child points back at its parent and a root points at nothing" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const tree: *abi_scene_tree.c.ke_scene_tree = @ptrCast(f.handle.ref);
    const parent = f.create("P", abi_ecs.c.KE_ENTITY_INVALID);
    const child = f.create("A", parent);

    try testing.expectEqual(parent, tree.parent.?(tree, child));
    try testing.expectEqual(tree.root.?(tree), tree.parent.?(tree, parent));
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, tree.first_child.?(tree, child));
}

test "walking an entity the tree never made answers nothing rather than guessing" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const tree: *abi_scene_tree.c.ke_scene_tree = @ptrCast(f.handle.ref);
    var stranger: abi_asset_resolver.c.ke_entity = abi_ecs.c.KE_ENTITY_INVALID;
    try R.check(f.ecs.vtable.entity_create.?(&f.ecs.vtable, &stranger));

    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, tree.parent.?(tree, stranger));
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, tree.first_child.?(tree, stranger));
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, tree.next_sibling.?(tree, stranger));
}

test "an empty or absent path finds nothing" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, f.find(""));
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, f.find(null));
}

test "a name nobody registered finds nothing" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, f.find("Unknown"));
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, f.find("/Unknown"));
}

test "a bare name finds a direct child of the root" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const child = f.create("Player", abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expectEqual(child, f.find("Player"));
}

test "a bare name searches the whole subtree, not just the root's children" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const inter = f.create("Intermediate", abi_ecs.c.KE_ENTITY_INVALID);
    const target = f.create("Target", inter);
    try testing.expectEqual(target, f.find("Target"));
}

test "a path walks segment by segment however it is anchored" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const world = f.create("World", abi_ecs.c.KE_ENTITY_INVALID);
    const player = f.create("Player", world);
    try testing.expectEqual(player, f.find("/World/Player"));
    try testing.expectEqual(player, f.find("World/Player"));
    try testing.expectEqual(player, f.find("./World/Player"));
}

test "a path whose last segment does not exist finds nothing" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    _ = f.create("World", abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, f.find("/World/Missing"));
}

test "a leading dot anchors the path at the root" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const world = f.create("World", abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expectEqual(world, f.find("./World"));
}

test "a trailing slash does not change what a path names" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const world = f.create("World", abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expectEqual(world, f.find("/World/"));
}

test "a deep relative path reaches a grandchild" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const a = f.create("A", abi_ecs.c.KE_ENTITY_INVALID);
    const b = f.create("B", a);
    const d = f.create("C", b);
    try testing.expectEqual(d, f.find("A/B/C"));
}

test "repeated slashes collapse instead of failing the walk" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const a = f.create("A", abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expectEqual(a, f.find("//A///"));
}

pub const RecordingCommands = struct {
    vtable: abi_ecs.c.ke_ecs_commands,
    ecs: *abi_ecs.c.ke_ecs,
    fns: [8]abi_ecs.c.ke_defer_fn = undefined,
    payloads: [8][128]u8 = undefined,
    count: usize = 0,

    fn of(self: ?*abi_ecs.c.ke_ecs_commands) *RecordingCommands {
        return @ptrCast(@alignCast(self.?.handle));
    }

    fn spawn(self: ?*abi_ecs.c.ke_ecs_commands, out_entity: [*c]abi_asset_resolver.c.ke_entity) callconv(.c) abi_result.c.ke_result {
        const r = of(self);
        return r.ecs.entity_reserve.?(r.ecs, out_entity);
    }

    fn defer_(self: ?*abi_ecs.c.ke_ecs_commands, func: abi_ecs.c.ke_defer_fn, user: ?*const anyopaque, size: usize) callconv(.c) abi_result.c.ke_result {
        const r = of(self);
        if (r.count == r.fns.len) return R.code(error.OutOfMemory);
        r.fns[r.count] = func;
        @memcpy(r.payloads[r.count][0..size], @as([*]const u8, @ptrCast(user.?))[0..size]);
        r.count += 1;
        return R.ok;
    }

    pub fn init(ecs: *abi_ecs.c.ke_ecs) RecordingCommands {
        var r: RecordingCommands = .{ .vtable = std.mem.zeroes(abi_ecs.c.ke_ecs_commands), .ecs = ecs };
        r.vtable.spawn = spawn;
        r.vtable.@"defer" = defer_;
        return r;
    }

    pub fn bind(self: *RecordingCommands) *abi_ecs.c.ke_ecs_commands {
        self.vtable.handle = self;
        return &self.vtable;
    }

    pub fn apply(self: *RecordingCommands) void {
        for (0..self.count) |i| _ = self.fns[i].?(self.ecs, &self.payloads[i]);
        self.count = 0;
    }
};

test "a deferred create exists only once the recorded commands are applied" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var rec = RecordingCommands.init(&f.ecs.vtable);
    const t = f.tree();
    var e: abi_asset_resolver.c.ke_entity = abi_ecs.c.KE_ENTITY_INVALID;
    try testing.expectEqual(R.ok, t.*.create_node_deferred.?(t, "Later", abi_ecs.c.KE_ENTITY_INVALID, rec.bind(), &e));
    try testing.expect(e != abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, f.find("Later"));

    rec.apply();
    try testing.expectEqual(e, f.find("Later"));
}

test "a deferred destroy removes the node only once the recorded commands are applied" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const node = f.create("Doomed", abi_ecs.c.KE_ENTITY_INVALID);
    var rec = RecordingCommands.init(&f.ecs.vtable);
    const t = f.tree();
    try testing.expectEqual(R.ok, t.*.destroy_node_deferred.?(t, node, rec.bind()));
    try testing.expectEqual(node, f.find("Doomed"));

    rec.apply();
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, f.find("Doomed"));
}

test "a deferred create without a command queue is refused" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const t = f.tree();
    var e: abi_asset_resolver.c.ke_entity = 7;
    try testing.expectEqual(R.code(error.InvalidArgument), t.*.create_node_deferred.?(t, "X", abi_ecs.c.KE_ENTITY_INVALID, null, &e));
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, e);
}

test "destroying the invalid entity is refused" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const t = f.tree();
    try testing.expectEqual(R.code(error.InvalidArgument), t.*.destroy_node.?(t, abi_ecs.c.KE_ENTITY_INVALID));
}

test "destroying a node takes its whole subtree with it" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const world = f.create("World", abi_ecs.c.KE_ENTITY_INVALID);
    _ = f.create("Player", world);
    _ = f.create("Enemy", world);

    const t = f.tree();
    try testing.expectEqual(R.ok, t.*.destroy_node.?(t, world));
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, f.find("World"));
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, f.find("Player"));
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, f.find("Enemy"));
}

test "a destroyed node is unlinked from its parent" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const child = f.create("X", abi_ecs.c.KE_ENTITY_INVALID);
    const t = f.tree();
    try testing.expectEqual(R.ok, t.*.destroy_node.?(t, child));
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, f.find("X"));
}

test "destroying a middle sibling leaves the chain walkable on both sides" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    _ = f.create("1", abi_ecs.c.KE_ENTITY_INVALID);
    const c2 = f.create("2", abi_ecs.c.KE_ENTITY_INVALID);
    _ = f.create("3", abi_ecs.c.KE_ENTITY_INVALID);

    const t = f.tree();
    try testing.expectEqual(R.ok, t.*.destroy_node.?(t, c2));

    try testing.expect(f.find("1") != abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expect(f.find("3") != abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, f.find("2"));
}

test "clearing the tree removes every child but keeps the root" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    _ = f.create("A", abi_ecs.c.KE_ENTITY_INVALID);
    _ = f.create("B", abi_ecs.c.KE_ENTITY_INVALID);

    const t = f.tree();
    try R.check(t.*.destroy_all.?(t));

    try testing.expect(t.*.root.?(t) != abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, f.find("A"));
    try testing.expectEqual(abi_ecs.c.KE_ENTITY_INVALID, f.find("B"));
}

test "a node with no local transform propagates to identity" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const n = f.create("N", abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expect(n != abi_ecs.c.KE_ENTITY_INVALID);
    const t = f.tree();
    t.*.propagate_transforms.?(t);

    const w = f.worldOf(n) orelse return error.MissingWorldTransform;
    for (w.matrix.m, 0..) |cell, i| {
        const expected: f32 = if (i % 5 == 0) 1.0 else 0.0;
        try testing.expectApproxEqAbs(expected, cell, matrix_tolerance);
    }
}

test "a child's translation composes with its parent's" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const parent = f.create("P", abi_ecs.c.KE_ENTITY_INVALID);
    const child = f.create("C", parent);
    try testing.expect(parent != abi_ecs.c.KE_ENTITY_INVALID);
    try testing.expect(child != abi_ecs.c.KE_ENTITY_INVALID);

    (f.transformOf(parent) orelse return error.MissingTransform).position = .{ .x = 10, .y = 0, .z = 0 };
    (f.transformOf(child) orelse return error.MissingTransform).position = .{ .x = 1, .y = 2, .z = 3 };

    const t = f.tree();
    t.*.propagate_transforms.?(t);

    const pw = f.worldOf(parent) orelse return error.MissingWorldTransform;
    try testing.expectApproxEqAbs(@as(f32, 10.0), pw.matrix.m[12], matrix_tolerance);

    const cw = f.worldOf(child) orelse return error.MissingWorldTransform;
    try testing.expectApproxEqAbs(@as(f32, 11.0), cw.matrix.m[12], matrix_tolerance);
    try testing.expectApproxEqAbs(@as(f32, 2.0), cw.matrix.m[13], matrix_tolerance);
    try testing.expectApproxEqAbs(@as(f32, 3.0), cw.matrix.m[14], matrix_tolerance);
}

test "a parent's scale stretches the offset its child sits at" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const parent = f.create("P", abi_ecs.c.KE_ENTITY_INVALID);
    const child = f.create("C", parent);

    (f.transformOf(parent) orelse return error.MissingTransform).scale = .{ .x = 2, .y = 2, .z = 2 };
    (f.transformOf(child) orelse return error.MissingTransform).position = .{ .x = 1, .y = 0, .z = 0 };

    const t = f.tree();
    t.*.propagate_transforms.?(t);

    const cw = f.worldOf(child) orelse return error.MissingWorldTransform;
    try testing.expectApproxEqAbs(@as(f32, 2.0), cw.matrix.m[12], matrix_tolerance);
    try testing.expectApproxEqAbs(@as(f32, 2.0), cw.matrix.m[0], matrix_tolerance);
}

test "a quarter turn about y sends the x axis to minus z" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const n = f.create("N", abi_ecs.c.KE_ENTITY_INVALID);
    const s: f32 = 0.70710678;
    (f.transformOf(n) orelse return error.MissingTransform).rotation = .{ .x = 0, .y = s, .z = 0, .w = s };

    const t = f.tree();
    t.*.propagate_transforms.?(t);

    const w = f.worldOf(n) orelse return error.MissingWorldTransform;
    try testing.expectApproxEqAbs(@as(f32, 0.0), w.matrix.m[0], matrix_tolerance);
    try testing.expectApproxEqAbs(@as(f32, 0.0), w.matrix.m[1], matrix_tolerance);
    try testing.expectApproxEqAbs(@as(f32, -1.0), w.matrix.m[2], matrix_tolerance);
}

test "a grandchild accumulates every translation on its chain" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const a = f.create("A", abi_ecs.c.KE_ENTITY_INVALID);
    const b = f.create("B", a);
    const d = f.create("D", b);

    (f.transformOf(a) orelse return error.MissingTransform).position = .{ .x = 1, .y = 0, .z = 0 };
    (f.transformOf(b) orelse return error.MissingTransform).position = .{ .x = 0, .y = 2, .z = 0 };
    (f.transformOf(d) orelse return error.MissingTransform).position = .{ .x = 0, .y = 0, .z = 4 };

    const t = f.tree();
    t.*.propagate_transforms.?(t);

    const dw = f.worldOf(d) orelse return error.MissingWorldTransform;
    try testing.expectApproxEqAbs(@as(f32, 1.0), dw.matrix.m[12], matrix_tolerance);
    try testing.expectApproxEqAbs(@as(f32, 2.0), dw.matrix.m[13], matrix_tolerance);
    try testing.expectApproxEqAbs(@as(f32, 4.0), dw.matrix.m[14], matrix_tolerance);
}

test "a tree without an ecs is refused as an invalid argument and leaves the handle zeroed" {
    var h: abi_scene_tree.c.ke_scene_tree_handle = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), ke_scene_tree_create(null, null, &h));
    try testing.expect(h.ref == null);
    try testing.expectEqual(R.code(error.InvalidArgument), ke_scene_tree_create(null, null, null));
}

test "a tree registers each transform with the field table its header generates" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    for (f.ecs.components[0..f.ecs.component_count]) |comp| {
        if (std.mem.eql(u8, comp.name, abi_spatial_contract.c.KE_COMPONENT_NAME_TRANSFORM))
            try testing.expectEqual(@as([*c]const abi_ecs.c.ke_component_field, &abi_spatial_contract.c.ke_transform_component_fields), comp.fields);
        if (std.mem.eql(u8, comp.name, abi_spatial_contract.c.KE_COMPONENT_NAME_TRANSFORM2D))
            try testing.expectEqual(@as([*c]const abi_ecs.c.ke_component_field, &abi_spatial_contract.c.ke_transform2d_component_fields), comp.fields);
    }
}

test "a tree whose component the ecs refuses is not created and fails with the ecs's code" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    f.ecs.refused = abi_framework_components.c.KE_COMPONENT_NAME_NAME;
    var h: abi_scene_tree.c.ke_scene_tree_handle = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), ke_scene_tree_create(&f.ecs.vtable, null, &h));
    try testing.expect(h.ref == null);
}

test "linking and unlinking a node each move the hierarchy generation" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const t = f.tree();
    const before = t.*.hierarchy_generation.?(t);
    try testing.expectEqual(before, t.*.hierarchy_generation.?(t));
    const n = f.create("Node", abi_ecs.c.KE_ENTITY_INVALID);
    const linked = t.*.hierarchy_generation.?(t);
    try testing.expect(linked != before);
    try testing.expectEqual(R.ok, t.*.destroy_node.?(t, n));
    try testing.expect(t.*.hierarchy_generation.?(t) != linked);
}

test "children first lists a node after its subtree and counts what the buffer cannot hold" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const a = f.create("A", abi_ecs.c.KE_ENTITY_INVALID);
    const a1 = f.create("A1", a);
    const a2 = f.create("A2", a);
    const b = f.create("B", abi_ecs.c.KE_ENTITY_INVALID);
    const t = f.tree();

    var nodes: [4]abi_asset_resolver.c.ke_entity = undefined;
    try testing.expectEqual(@as(u32, 4), t.*.children_first.?(t, &nodes, nodes.len));
    try testing.expectEqualSlices(abi_asset_resolver.c.ke_entity, &.{ a1, a2, a, b }, &nodes);

    var two: [2]abi_asset_resolver.c.ke_entity = undefined;
    try testing.expectEqual(@as(u32, 4), t.*.children_first.?(t, &two, two.len));
    try testing.expectEqualSlices(abi_asset_resolver.c.ke_entity, &.{ a1, a2 }, &two);
    try testing.expectEqual(@as(u32, 4), t.*.children_first.?(t, null, 0));
}

test "creating nodes and destroying the tree leaves no block allocated" {
    var f: Fixture = undefined;
    try f.init();
    const world = f.create("World", abi_ecs.c.KE_ENTITY_INVALID);
    _ = f.create("Player", world);
    f.deinit();
    try heap.expectNoLeaks();
}
