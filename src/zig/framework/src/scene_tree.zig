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
    ecs: *c.ke_ecs,
    root: c.ke_entity,
    transform_cid: c.ke_component_id,
    transform2d_cid: c.ke_component_id,
    world_transform_cid: c.ke_component_id,
    hierarchy_cid: c.ke_component_id,
    name_cid: c.ke_component_id,
    hierarchy: c.ke_scene_hierarchy_handle,
};

fn stateOf(self: *c.ke_scene_tree) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn getHierarchy(s: *State, e: c.ke_entity) ?*c.ke_hierarchy_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.hierarchy_cid)));
}

fn getName(s: *State, e: c.ke_entity) ?*const c.ke_name_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.name_cid)));
}

fn getTransform(s: *State, e: c.ke_entity) ?*c.ke_transform_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.transform_cid)));
}

fn getTransform2d(s: *State, e: c.ke_entity) ?*const c.ke_transform2d_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.transform2d_cid)));
}

fn getWorldTransform(s: *State, e: c.ke_entity) ?*c.ke_world_transform_component {
    return @ptrCast(@alignCast(s.ecs.component_get.?(s.ecs, e, s.world_transform_cid)));
}

/// Resolves an existing component cid by name, registering it when absent.
fn ensureComponent(ecs: *c.ke_ecs, name: [*c]const u8, size: usize) c.ke_component_id {
    var meta: c.ke_component_meta = undefined;
    if (ecs.component_lookup.?(ecs, name, &meta, null)) return meta.cid;
    return ecs.component_register.?(ecs, name, size, null, 0, null);
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

fn vtRoot(self_in: ?*c.ke_scene_tree) callconv(.c) c.ke_entity {
    const self = self_in orelse return c.KE_ENTITY_INVALID;
    if (self.handle == null) return c.KE_ENTITY_INVALID;
    return stateOf(self).root;
}

/// Attaches the scene-graph components to an entity and prepends it into its
/// parent's child list. Valid only where structural changes are legal.
fn populateNode(s: *State, entity: c.ke_entity, name: [*c]const u8, parent: c.ke_entity) bool {
    if (s.ecs.component_add.?(s.ecs, entity, s.world_transform_cid) == null or
        s.ecs.component_add.?(s.ecs, entity, s.hierarchy_cid) == null or
        s.ecs.component_add.?(s.ecs, entity, s.name_cid) == null)
    {
        s.ecs.entity_destroy.?(s.ecs, entity);
        return false;
    }

    if (getWorldTransform(s, entity)) |w| {
        w.matrix = identityMatrix();
    }

    if (getHierarchy(s, entity)) |h| {
        h.parent = parent;
        h.first_child = c.KE_ENTITY_INVALID;
        h.last_child = c.KE_ENTITY_INVALID;
        h.next_sibling = c.KE_ENTITY_INVALID;
        h.prev_sibling = c.KE_ENTITY_INVALID;
    }

    if (@as(?*c.ke_name_component, @ptrCast(@alignCast(
        s.ecs.component_get.?(s.ecs, entity, s.name_cid),
    )))) |n| {
        writeName(&n.name, name);
    }

    const h = getHierarchy(s, entity);
    const ph = getHierarchy(s, parent);
    if (ph != null and h != null) {
        h.?.prev_sibling = ph.?.last_child;
        if (ph.?.last_child != c.KE_ENTITY_INVALID) {
            if (getHierarchy(s, ph.?.last_child)) |sib| sib.next_sibling = entity;
        } else {
            ph.?.first_child = entity;
        }
        ph.?.last_child = entity;
    }
    return true;
}

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

    const entity = s.ecs.entity_create.?(s.ecs);
    if (entity == c.KE_ENTITY_INVALID) return c.KE_ENTITY_INVALID;
    if (!populateNode(s, entity, name, parent)) return c.KE_ENTITY_INVALID;
    return entity;
}

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
    const h = getHierarchy(s, entity) orelse return;
    const h_prev = h.prev_sibling;
    const h_next = h.next_sibling;
    const h_parent = h.parent;

    if (h_parent != c.KE_ENTITY_INVALID) {
        if (getHierarchy(s, h_parent)) |ph| {
            if (ph.first_child == entity) ph.first_child = h_next;
            if (ph.last_child == entity) ph.last_child = h_prev;
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

    const rh = getHierarchy(s, s.root) orelse return;
    var child = rh.first_child;
    while (child != c.KE_ENTITY_INVALID) {
        const next = if (getHierarchy(s, child)) |ch| ch.next_sibling else c.KE_ENTITY_INVALID;
        destroyEntitiesRecursive(s, child);
        child = next;
    }
    if (getHierarchy(s, s.root)) |h| {
        h.first_child = c.KE_ENTITY_INVALID;
        h.last_child = c.KE_ENTITY_INVALID;
    }
}

fn propagateRecursive(s: *State, entity: c.ke_entity, parent_world: *const c.ke_mat4) void {
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

fn vtDestroy(self_in: ?*c.ke_scene_tree) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    if (s.hierarchy.destroy) |d| d(s.hierarchy.ref);
    destroyEntitiesRecursive(s, s.root);
    heap.gpa.destroy(s);
}

export fn ke_scene_tree_create(
    ecs_in: ?*c.ke_ecs,
    runtime: ?*c.ke_runtime,
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
        .transform2d_cid = 0,
        .world_transform_cid = 0,
        .hierarchy_cid = 0,
        .name_cid = 0,
        .hierarchy = std.mem.zeroes(c.ke_scene_hierarchy_handle),
    };

    s.transform_cid = ensureComponent(ecs, c.KE_COMPONENT_NAME_TRANSFORM, @sizeOf(c.ke_transform_component));
    s.transform2d_cid = ensureComponent(ecs, c.KE_COMPONENT_NAME_TRANSFORM_2D, @sizeOf(c.ke_transform2d_component));
    s.world_transform_cid = ensureComponent(ecs, c.KE_COMPONENT_NAME_WORLD_TRANSFORM, @sizeOf(c.ke_world_transform_component));
    s.hierarchy_cid = ensureComponent(ecs, c.KE_COMPONENT_NAME_HIERARCHY, @sizeOf(c.ke_hierarchy_component));
    s.name_cid = ensureComponent(ecs, c.KE_COMPONENT_NAME_NAME, @sizeOf(c.ke_name_component));

    s.root = ecs.entity_create.?(ecs);
    if (s.root == c.KE_ENTITY_INVALID) {
        heap.gpa.destroy(s);
        E.fail(out_error, .general, "root entity creation failed", @src());
        return null_handle;
    }
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
        h.last_child = c.KE_ENTITY_INVALID;
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

    if (runtime) |rt| {
        s.hierarchy = c.ke_scene_hierarchy_create(rt, ecs, out_error);
        if (s.hierarchy.ref == null) {
            ecs.entity_destroy.?(ecs, s.root);
            heap.gpa.destroy(s);
            return null_handle;
        }
    }

    return .{ .ref = &s.api, .destroy = vtDestroy };
}

const testing = std.testing;

const matrix_tolerance: f32 = 1e-5;

const fake_max_components = 16;
const fake_max_entities = 128;

const FakeComponent = struct {
    name: []const u8,
    size: usize,
};

/// Exposed so a sibling implementation defined over the scene graph — the script
/// host resolving a node's relatives — can be tested against a real tree instead
/// of a second stand-in that would drift from this one.
pub const FakeEcs = struct {
    vtable: c.ke_ecs,
    arena: std.heap.ArenaAllocator,
    components: [fake_max_components]FakeComponent,
    component_count: usize,
    alive: [fake_max_entities]bool,
    storage: [fake_max_entities][fake_max_components]?[*]u8,
    next_entity: c.ke_entity,
};

fn fakeEcsOf(self: ?*c.ke_ecs) *FakeEcs {
    return @ptrCast(@alignCast(self.?.handle));
}

fn fakeSlot(f: *FakeEcs, entity: c.ke_entity, cid: c.ke_component_id) ?*?[*]u8 {
    if (entity == c.KE_ENTITY_INVALID or entity > fake_max_entities) return null;
    const row = entity - 1;
    if (!f.alive[row]) return null;
    if (cid == 0 or cid > f.component_count) return null;
    return &f.storage[row][cid - 1];
}

fn fakeEntityCreate(self: ?*c.ke_ecs) callconv(.c) c.ke_entity {
    const f = fakeEcsOf(self);
    if (f.next_entity >= fake_max_entities) return c.KE_ENTITY_INVALID;
    f.next_entity += 1;
    f.alive[f.next_entity - 1] = true;
    return f.next_entity;
}

fn fakeEntityReserve(self: ?*c.ke_ecs) callconv(.c) c.ke_entity {
    return fakeEntityCreate(self);
}

fn fakeEntityDestroy(self: ?*c.ke_ecs, entity: c.ke_entity) callconv(.c) void {
    const f = fakeEcsOf(self);
    if (entity == c.KE_ENTITY_INVALID or entity > fake_max_entities) return;
    const row = entity - 1;
    f.alive[row] = false;
    for (&f.storage[row]) |*cell| cell.* = null;
}

fn fakeComponentRegister(
    self: ?*c.ke_ecs,
    name: [*c]const u8,
    element_size: usize,
    fields: [*c]const c.ke_component_field,
    field_count: u32,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_component_id {
    _ = fields;
    _ = field_count;
    _ = out_error;
    const f = fakeEcsOf(self);
    const wanted = std.mem.span(name);
    for (f.components[0..f.component_count], 0..) |comp, i| {
        if (std.mem.eql(u8, comp.name, wanted)) return @intCast(i + 1);
    }
    if (f.component_count >= fake_max_components) return 0;
    f.components[f.component_count] = .{ .name = wanted, .size = element_size };
    f.component_count += 1;
    return @intCast(f.component_count);
}

fn fakeComponentLookup(
    self: ?*c.ke_ecs,
    name: [*c]const u8,
    out_meta: [*c]c.ke_component_meta,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    _ = out_error;
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
    self: ?*c.ke_ecs,
    entity: c.ke_entity,
    component: c.ke_component_id,
) callconv(.c) ?*anyopaque {
    const f = fakeEcsOf(self);
    const slot = fakeSlot(f, entity, component) orelse return null;
    if (slot.*) |existing| return existing;
    const size = f.components[component - 1].size;
    const block = f.arena.allocator().alignedAlloc(u8, .of(u64), @max(size, 1)) catch return null;
    @memset(block, 0);
    slot.* = block.ptr;
    return block.ptr;
}

fn fakeComponentRemove(
    self: ?*c.ke_ecs,
    entity: c.ke_entity,
    component: c.ke_component_id,
) callconv(.c) void {
    const f = fakeEcsOf(self);
    const slot = fakeSlot(f, entity, component) orelse return;
    slot.* = null;
}

fn fakeComponentGet(
    self: ?*c.ke_ecs,
    entity: c.ke_entity,
    component: c.ke_component_id,
) callconv(.c) ?*anyopaque {
    const f = fakeEcsOf(self);
    const slot = fakeSlot(f, entity, component) orelse return null;
    return slot.*;
}

fn fakeComponentSize(self: ?*c.ke_ecs, cid: c.ke_component_id) callconv(.c) usize {
    const f = fakeEcsOf(self);
    if (cid == 0 or cid > f.component_count) return 0;
    return f.components[cid - 1].size;
}

pub const Fixture = struct {
    ecs: FakeEcs,
    handle: c.ke_scene_tree_handle,

    pub fn init(self: *Fixture) !void {
        self.ecs.arena = std.heap.ArenaAllocator.init(testing.allocator);
        self.ecs.component_count = 0;
        self.ecs.next_entity = 0;
        @memset(&self.ecs.alive, false);
        for (&self.ecs.storage) |*row| @memset(row, null);
        self.ecs.vtable = std.mem.zeroes(c.ke_ecs);
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

        self.handle = ke_scene_tree_create(&self.ecs.vtable, null, null);
        try testing.expect(self.handle.ref != null);
    }

    pub fn deinit(self: *Fixture) void {
        if (self.handle.destroy) |d| d(self.handle.ref);
        self.ecs.arena.deinit();
    }

    pub fn tree(self: *Fixture) [*c]c.ke_scene_tree {
        return self.handle.ref;
    }

    pub fn create(self: *Fixture, name: [*c]const u8, parent: c.ke_entity) c.ke_entity {
        const t = self.tree();
        return t.*.create_node.?(t, name, parent, null, null);
    }

    fn find(self: *Fixture, path: [*c]const u8) c.ke_entity {
        const t = self.tree();
        return t.*.find_node.?(t, path, null);
    }

    fn hierarchyOf(self: *Fixture, e: c.ke_entity) ?*c.ke_hierarchy_component {
        var meta: c.ke_component_meta = undefined;
        if (!fakeComponentLookup(&self.ecs.vtable, c.KE_COMPONENT_NAME_HIERARCHY, &meta, null)) return null;
        return @ptrCast(@alignCast(fakeComponentGet(&self.ecs.vtable, e, meta.cid)));
    }

    fn transformOf(self: *Fixture, e: c.ke_entity) ?*c.ke_transform_component {
        var meta: c.ke_component_meta = undefined;
        if (!fakeComponentLookup(&self.ecs.vtable, c.KE_COMPONENT_NAME_TRANSFORM, &meta, null)) return null;
        if (fakeComponentGet(&self.ecs.vtable, e, meta.cid)) |existing| {
            return @ptrCast(@alignCast(existing));
        }
        const added: ?*c.ke_transform_component =
            @ptrCast(@alignCast(fakeComponentAdd(&self.ecs.vtable, e, meta.cid)));
        if (added) |t| {
            t.position = .{ .x = 0, .y = 0, .z = 0 };
            t.rotation = .{ .x = 0, .y = 0, .z = 0, .w = 1 };
            t.scale = .{ .x = 1, .y = 1, .z = 1 };
        }
        return added;
    }

    fn worldOf(self: *Fixture, e: c.ke_entity) ?*c.ke_world_transform_component {
        var meta: c.ke_component_meta = undefined;
        if (!fakeComponentLookup(&self.ecs.vtable, c.KE_COMPONENT_NAME_WORLD_TRANSFORM, &meta, null)) return null;
        return @ptrCast(@alignCast(fakeComponentGet(&self.ecs.vtable, e, meta.cid)));
    }
};

test "a fresh tree has one stable root" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const t = f.tree();
    const r = t.*.root.?(t);
    try testing.expect(r != c.KE_ENTITY_INVALID);
    try testing.expectEqual(r, t.*.root.?(t));
}

test "a node created without a parent lands under the root" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const child = f.create("X", c.KE_ENTITY_INVALID);
    try testing.expect(child != c.KE_ENTITY_INVALID);
    try testing.expectEqual(child, f.find("X"));
}

test "a node created with an explicit parent is reachable through it" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const parent = f.create("Parent", c.KE_ENTITY_INVALID);
    const child = f.create("Child", parent);
    try testing.expect(child != c.KE_ENTITY_INVALID);
    try testing.expectEqual(child, f.find("Parent/Child"));
}

test "every sibling under one parent stays reachable and points back at it" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const parent = f.create("P", c.KE_ENTITY_INVALID);
    const a = f.create("A", parent);
    const b = f.create("B", parent);
    const d = f.create("C", parent);
    try testing.expect(a != c.KE_ENTITY_INVALID);
    try testing.expect(b != c.KE_ENTITY_INVALID);
    try testing.expect(d != c.KE_ENTITY_INVALID);

    try testing.expectEqual(a, f.find("P/A"));
    try testing.expectEqual(b, f.find("P/B"));
    try testing.expectEqual(d, f.find("P/C"));

    const ph = f.hierarchyOf(parent) orelse return error.MissingHierarchy;
    var walked: usize = 0;
    var cur = ph.first_child;
    while (cur != c.KE_ENTITY_INVALID and walked < fake_max_entities) : (walked += 1) {
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

    const parent = f.create("P", c.KE_ENTITY_INVALID);
    const a = f.create("A", parent);
    const b = f.create("B", parent);
    const d = f.create("C", parent);

    const ph = f.hierarchyOf(parent) orelse return error.MissingHierarchy;
    var order: [3]c.ke_entity = .{ 0, 0, 0 };
    var walked: usize = 0;
    var cur = ph.first_child;
    while (cur != c.KE_ENTITY_INVALID and walked < order.len) : (walked += 1) {
        order[walked] = cur;
        const ch = f.hierarchyOf(cur) orelse return error.MissingHierarchy;
        cur = ch.next_sibling;
    }
    try testing.expectEqual(a, order[0]);
    try testing.expectEqual(b, order[1]);
    try testing.expectEqual(d, order[2]);
    try testing.expectEqual(d, ph.last_child);
}

test "an empty or absent path finds nothing" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    try testing.expectEqual(c.KE_ENTITY_INVALID, f.find(""));
    try testing.expectEqual(c.KE_ENTITY_INVALID, f.find(null));
}

test "a name nobody registered finds nothing" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    try testing.expectEqual(c.KE_ENTITY_INVALID, f.find("Unknown"));
    try testing.expectEqual(c.KE_ENTITY_INVALID, f.find("/Unknown"));
}

test "a bare name finds a direct child of the root" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const child = f.create("Player", c.KE_ENTITY_INVALID);
    try testing.expectEqual(child, f.find("Player"));
}

test "a bare name searches the whole subtree, not just the root's children" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const inter = f.create("Intermediate", c.KE_ENTITY_INVALID);
    const target = f.create("Target", inter);
    try testing.expectEqual(target, f.find("Target"));
}

test "a path walks segment by segment however it is anchored" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const world = f.create("World", c.KE_ENTITY_INVALID);
    const player = f.create("Player", world);
    try testing.expectEqual(player, f.find("/World/Player"));
    try testing.expectEqual(player, f.find("World/Player"));
    try testing.expectEqual(player, f.find("./World/Player"));
}

test "a path whose last segment does not exist finds nothing" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    _ = f.create("World", c.KE_ENTITY_INVALID);
    try testing.expectEqual(c.KE_ENTITY_INVALID, f.find("/World/Missing"));
}

test "a leading dot anchors the path at the root" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const world = f.create("World", c.KE_ENTITY_INVALID);
    try testing.expectEqual(world, f.find("./World"));
}

test "a trailing slash does not change what a path names" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const world = f.create("World", c.KE_ENTITY_INVALID);
    try testing.expectEqual(world, f.find("/World/"));
}

test "a deep relative path reaches a grandchild" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const a = f.create("A", c.KE_ENTITY_INVALID);
    const b = f.create("B", a);
    const d = f.create("C", b);
    try testing.expectEqual(d, f.find("A/B/C"));
}

test "repeated slashes collapse instead of failing the walk" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const a = f.create("A", c.KE_ENTITY_INVALID);
    try testing.expectEqual(a, f.find("//A///"));
}

test "destroying the invalid entity is refused" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const t = f.tree();
    try testing.expect(!t.*.destroy_node.?(t, c.KE_ENTITY_INVALID, null, null));
}

test "destroying a node takes its whole subtree with it" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const world = f.create("World", c.KE_ENTITY_INVALID);
    _ = f.create("Player", world);
    _ = f.create("Enemy", world);

    const t = f.tree();
    try testing.expect(t.*.destroy_node.?(t, world, null, null));
    try testing.expectEqual(c.KE_ENTITY_INVALID, f.find("World"));
    try testing.expectEqual(c.KE_ENTITY_INVALID, f.find("Player"));
    try testing.expectEqual(c.KE_ENTITY_INVALID, f.find("Enemy"));
}

test "a destroyed node is unlinked from its parent" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const child = f.create("X", c.KE_ENTITY_INVALID);
    const t = f.tree();
    try testing.expect(t.*.destroy_node.?(t, child, null, null));
    try testing.expectEqual(c.KE_ENTITY_INVALID, f.find("X"));
}

test "destroying a middle sibling leaves the chain walkable on both sides" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    _ = f.create("1", c.KE_ENTITY_INVALID);
    const c2 = f.create("2", c.KE_ENTITY_INVALID);
    _ = f.create("3", c.KE_ENTITY_INVALID);

    const t = f.tree();
    try testing.expect(t.*.destroy_node.?(t, c2, null, null));

    try testing.expect(f.find("1") != c.KE_ENTITY_INVALID);
    try testing.expect(f.find("3") != c.KE_ENTITY_INVALID);
    try testing.expectEqual(c.KE_ENTITY_INVALID, f.find("2"));
}

test "clearing the tree removes every child but keeps the root" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    _ = f.create("A", c.KE_ENTITY_INVALID);
    _ = f.create("B", c.KE_ENTITY_INVALID);

    const t = f.tree();
    t.*.destroy_all.?(t);

    try testing.expect(t.*.root.?(t) != c.KE_ENTITY_INVALID);
    try testing.expectEqual(c.KE_ENTITY_INVALID, f.find("A"));
    try testing.expectEqual(c.KE_ENTITY_INVALID, f.find("B"));
}

test "a node with no local transform propagates to identity" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const n = f.create("N", c.KE_ENTITY_INVALID);
    try testing.expect(n != c.KE_ENTITY_INVALID);
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

    const parent = f.create("P", c.KE_ENTITY_INVALID);
    const child = f.create("C", parent);
    try testing.expect(parent != c.KE_ENTITY_INVALID);
    try testing.expect(child != c.KE_ENTITY_INVALID);

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

    const parent = f.create("P", c.KE_ENTITY_INVALID);
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

    const n = f.create("N", c.KE_ENTITY_INVALID);
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

    const a = f.create("A", c.KE_ENTITY_INVALID);
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

test "a tree without an ecs is never created" {
    try testing.expect(ke_scene_tree_create(null, null, null).ref == null);
}

test "a tree refused for a missing ecs names the shared invalid-argument type" {
    var err: [*c]c.ke_error = null;
    try testing.expect(ke_scene_tree_create(null, null, &err).ref == null);
    try testing.expect(err != null);
    try testing.expect(err.*.type != null);
    try testing.expectEqual(E.typeOf(.invalid_argument), err.*.type);
}
