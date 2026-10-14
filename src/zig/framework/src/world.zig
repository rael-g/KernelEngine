//! The world: the handle that carries the ecs, runtime and scene tree the framework works on, and
//! the registry of how a scene fills each component.

const std = @import("std");

const c = @import("c.zig").c;
const heap = @import("heap");

const E = @import("kerror").Errors(c);

const apply = @import("components_apply.zig");

const apply_initial_capacity: u32 = 16;

/// One entry per component id. The apply half (`fn_ptr`, `ctx`) and the fields half (`fields`,
/// `field_count`) are written by separate registration slots, so either half may stay unset.
const ApplyEntry = struct {
    cid: c.ke_component_id,
    fn_ptr: c.ke_component_apply_fn,
    ctx: ?*anyopaque,
    fields: ?[*]const c.ke_component_field,
    field_count: u32,
};

/// The state of one world, held by `Block`. The pointers it holds are borrowed from the creation
/// params and never freed. `apply_registry` stays null until the first registration, and
/// `apply_capacity` is the length of the buffer it points to, which is what `worldDestroy` frees.
const State = struct {
    scheduler: ?*c.ke_scheduler,
    ecs: ?*c.ke_ecs,
    runtime: ?*c.ke_runtime,
    scene_tree: ?*c.ke_scene_tree,
    project_root: [*c]const u8,
    logger: ?*c.ke_logger,
    signal_bus: ?*c.ke_signal_bus,

    apply_registry: ?[*]ApplyEntry,
    apply_count: u32,
    apply_capacity: u32,
};

/// The single allocation of a world: the state and the vtable. The `ref` of the handle returned by
/// `ke_world_create` points at the `world` field, and `handle` of that vtable points at `state`,
/// so the destroy function reaches both from either.
const Block = struct {
    state: State,
    world: c.ke_world,
};

fn stateOf(self: *c.ke_world) *State {
    return @ptrCast(@alignCast(self.handle));
}

/// Returns the logger given at creation. The world only borrows it, and null if none was given.
pub fn loggerOf(self: *c.ke_world) ?*c.ke_logger {
    return stateOf(self).logger;
}

/// Returns the signal bus given at creation. The world only borrows it, and null if none was given.
pub fn signalBusOf(self: *c.ke_world) ?*c.ke_signal_bus {
    return stateOf(self).signal_bus;
}

/// Slot `ecs`. Returns the ecs given at creation, or null for a null world.
fn worldEcs(self_in: ?*c.ke_world) callconv(.c) ?*c.ke_ecs {
    const self = self_in orelse return null;
    return stateOf(self).ecs;
}

/// Slot `runtime`. Returns the runtime given at creation, or null for a null world.
fn worldRuntime(self_in: ?*c.ke_world) callconv(.c) ?*c.ke_runtime {
    const self = self_in orelse return null;
    return stateOf(self).runtime;
}

/// Slot `scene_tree`. Returns the scene tree given at creation, null when none was given or for a
/// null world.
fn worldSceneTree(self_in: ?*c.ke_world) callconv(.c) ?*c.ke_scene_tree {
    const self = self_in orelse return null;
    return stateOf(self).scene_tree;
}

/// Returns the entry for the given component id, appending an empty one when there is none. Both
/// registration slots go through it. Appending can replace the whole buffer, so an entry pointer
/// kept across a later call is not valid after that call. On an allocation failure the error is
/// set, null is returned and the registry is unchanged.
fn entryFor(s: *State, cid: c.ke_component_id, out_error: [*c][*c]c.ke_error) ?*ApplyEntry {
    if (s.apply_registry) |reg| {
        for (reg[0..s.apply_count]) |*entry| {
            if (entry.cid == cid) return entry;
        }
    }

    if (s.apply_count == s.apply_capacity) {
        const cap = if (s.apply_capacity != 0) s.apply_capacity * 2 else apply_initial_capacity;
        const new_buf = heap.gpa.alloc(ApplyEntry, cap) catch {
            E.fail(out_error, .out_of_memory, "apply registry allocation failed", @src());
            return null;
        };
        if (s.apply_registry) |old| {
            @memcpy(new_buf[0..s.apply_count], old[0..s.apply_count]);
            heap.gpa.free(old[0..s.apply_capacity]);
        }
        s.apply_registry = new_buf.ptr;
        s.apply_capacity = cap;
    }

    const entry = &s.apply_registry.?[s.apply_count];
    entry.* = .{ .cid = cid, .fn_ptr = null, .ctx = null, .fields = null, .field_count = 0 };
    s.apply_count += 1;
    return entry;
}

/// Slot `register_component_apply`. Sets the callback and context of a component id, leaving its
/// field table alone, and replaces a callback registered before. Fails as an invalid argument for
/// a null world or callback, and as out of memory when the registry cannot grow; both return
/// false.
fn worldRegisterComponentApply(
    self_in: ?*c.ke_world,
    cid: c.ke_component_id,
    apply_fn: c.ke_component_apply_fn,
    ctx: ?*anyopaque,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null or apply_fn == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const entry = entryFor(stateOf(self), cid, out_error) orelse return false;
    entry.fn_ptr = apply_fn;
    entry.ctx = ctx;
    return true;
}

/// Slot `register_component_fields`. Sets the field table of a component id, leaving its callback
/// alone; the table is borrowed, not copied. Fails as an invalid argument for a null world or
/// table or a zero count, and as out of memory when the registry cannot grow; both return false.
fn worldRegisterComponentFields(
    self_in: ?*c.ke_world,
    cid: c.ke_component_id,
    fields: [*c]const c.ke_component_field,
    field_count: u32,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null or fields == null or field_count == 0) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const entry = entryFor(stateOf(self), cid, out_error) orelse return false;
    entry.fields = fields;
    entry.field_count = field_count;
    return true;
}

/// Slot `get_component_fields`. Returns the table registered for the id and writes its length to
/// `out_count` when that is non-null. An id whose entry has no fields returns null, not
/// an empty table.
fn worldGetComponentFields(
    self_in: ?*c.ke_world,
    cid: c.ke_component_id,
    out_count: [*c]u32,
) callconv(.c) [*c]const c.ke_component_field {
    const self = self_in orelse return null;
    if (self.handle == null) return null;
    const s = stateOf(self);
    const reg = s.apply_registry orelse return null;
    for (reg[0..s.apply_count]) |entry| {
        if (entry.cid != cid) continue;
        const f = entry.fields orelse return null;
        if (out_count != null) out_count.* = entry.field_count;
        return f;
    }
    return null;
}

/// Slot `get_component_apply`. Returns the callback registered for the id and writes its context.
/// The context is written whenever the id has an entry, so a null callback can still come back
/// together with a context.
fn worldGetComponentApply(
    self_in: ?*c.ke_world,
    cid: c.ke_component_id,
    out_ctx: [*c]?*anyopaque,
) callconv(.c) c.ke_component_apply_fn {
    const self = self_in orelse return null;
    if (self.handle == null) return null;
    const s = stateOf(self);
    const reg = s.apply_registry orelse return null;
    for (reg[0..s.apply_count]) |entry| {
        if (entry.cid != cid) continue;
        if (out_ctx != null) out_ctx.* = entry.ctx;
        return entry.fn_ptr;
    }
    return null;
}

/// The destroy function of the handle. After it returns the registry buffer and the block are
/// freed; the ecs, runtime and other borrowed objects are untouched.
fn worldDestroy(self_in: ?*c.ke_world) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    if (s.apply_registry) |reg| heap.gpa.free(reg[0..s.apply_capacity]);
    heap.gpa.destroy(@as(*Block, @fieldParentPtr("state", s)));
}

/// Called by `ke_world_create` once for each builtin component. The ecs registration comes first,
/// and its result is the only one this function returns.
fn registerBuiltin(
    world: *c.ke_world,
    e: *c.ke_ecs,
    name: [*c]const u8,
    size: usize,
    apply_fn: c.ke_component_apply_fn,
    fields: ?[*]const c.ke_component_field,
    field_count: u32,
    out_error: [*c][*c]c.ke_error,
) bool {
    const cid = e.component_register.?(e, name, size, fields orelse null, field_count, out_error);
    if (cid == 0) return false;
    if (fields) |f| _ = world.register_component_fields.?(world, cid, f, field_count, null);
    if (apply_fn != null) _ = world.register_component_apply.?(world, cid, apply_fn, null, null);
    return true;
}

/// Factory. Returns a handle whose `ref` is the world and whose destroy is `worldDestroy`, after
/// registering the transform, 2D transform and world transform components on the ecs. A null
/// params pointer, or a missing ecs or runtime, fails as an invalid argument; a failed block
/// allocation fails as out of memory; a failed builtin registration reports the ecs error. Each
/// returns a null handle.
export fn ke_world_create(
    params_in: ?*const c.ke_world_params,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_world_handle {
    const null_handle = std.mem.zeroes(c.ke_world_handle);

    const params = params_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null_handle;
    };
    if (params.ecs == null or params.runtime == null) {
        E.fail(out_error, .invalid_argument, "ecs and runtime are required", @src());
        return null_handle;
    }

    const block = heap.gpa.create(Block) catch {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return null_handle;
    };
    block.* = std.mem.zeroes(Block);

    const state = &block.state;
    const world = &block.world;

    state.scheduler = params.scheduler;
    state.ecs = params.ecs;
    state.runtime = params.runtime;
    state.scene_tree = params.scene_tree;
    state.project_root = params.project_root;
    state.logger = params.logger;
    state.signal_bus = params.signal_bus;

    world.handle = state;
    world.ecs = worldEcs;
    world.runtime = worldRuntime;
    world.scene_tree = worldSceneTree;
    world.register_component_fields = worldRegisterComponentFields;
    world.get_component_fields = worldGetComponentFields;
    world.register_component_apply = worldRegisterComponentApply;
    world.get_component_apply = worldGetComponentApply;

    const e = params.ecs.?;
    const registered =
        registerBuiltin(world, e, c.KE_COMPONENT_NAME_TRANSFORM, @sizeOf(c.ke_transform_component), apply.ke_framework_apply_transform, &c.ke_transform_component_fields, c.ke_transform_component_fields.len, out_error) and
        registerBuiltin(world, e, c.KE_COMPONENT_NAME_TRANSFORM2D, @sizeOf(c.ke_transform2d_component), apply.ke_framework_apply_transform2d, &c.ke_transform2d_component_fields, c.ke_transform2d_component_fields.len, out_error) and
        registerBuiltin(world, e, c.KE_COMPONENT_NAME_WORLD_TRANSFORM, @sizeOf(c.ke_world_transform_component), null, null, 0, out_error);
    if (!registered) {
        worldDestroy(world);
        return null_handle;
    }

    return .{ .ref = world, .destroy = worldDestroy };
}

const testing = std.testing;

const StubEcs = struct {
    vtable: c.ke_ecs,
    next_cid: c.ke_component_id,
    next_entity: c.ke_entity,
};

fn stubEcsOf(self: ?*c.ke_ecs) *StubEcs {
    return @ptrCast(@alignCast(self.?.handle));
}

fn stubComponentLookup(
    self: ?*c.ke_ecs,
    name: [*c]const u8,
    out_meta: [*c]c.ke_component_meta,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    _ = self;
    _ = name;
    _ = out_meta;
    _ = out_error;
    return false;
}

fn stubComponentRegister(
    self: ?*c.ke_ecs,
    name: [*c]const u8,
    element_size: usize,
    fields: [*c]const c.ke_component_field,
    field_count: u32,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_component_id {
    _ = fields;
    _ = field_count;
    _ = name;
    _ = element_size;
    _ = out_error;
    const s = stubEcsOf(self);
    s.next_cid += 1;
    return s.next_cid;
}

fn stubEntityCreate(self: ?*c.ke_ecs) callconv(.c) c.ke_entity {
    const s = stubEcsOf(self);
    s.next_entity += 1;
    return s.next_entity;
}

fn stubEcsInit(s: *StubEcs) void {
    s.* = std.mem.zeroes(StubEcs);
    s.vtable.handle = s;
    s.vtable.component_lookup = stubComponentLookup;
    s.vtable.component_register = stubComponentRegister;
    s.vtable.entity_create = stubEntityCreate;
}

test "a world hands back the ecs and runtime it was built with, and no tree it never got" {
    var ecs: StubEcs = undefined;
    stubEcsInit(&ecs);
    var runtime = std.mem.zeroes(c.ke_runtime);

    var params = std.mem.zeroes(c.ke_world_params);
    params.ecs = &ecs.vtable;
    params.runtime = &runtime;
    params.project_root = "res/";

    const h = ke_world_create(&params, null);
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);

    const w = h.ref.?;
    try testing.expectEqual(@as(?*c.ke_ecs, &ecs.vtable), w.*.ecs.?(w));
    try testing.expectEqual(@as(?*c.ke_runtime, &runtime), w.*.runtime.?(w));
    try testing.expect(w.*.scene_tree.?(w) == null);

    const e = w.*.ecs.?(w).?;
    try testing.expect(e.*.entity_create.?(e) != c.KE_ENTITY_INVALID);
}

test "two worlds never share the ecs, and destroying one leaves the other alive" {
    var ecs_a: StubEcs = undefined;
    var ecs_b: StubEcs = undefined;
    stubEcsInit(&ecs_a);
    stubEcsInit(&ecs_b);
    var runtime = std.mem.zeroes(c.ke_runtime);

    var pa = std.mem.zeroes(c.ke_world_params);
    pa.ecs = &ecs_a.vtable;
    pa.runtime = &runtime;
    var pb = std.mem.zeroes(c.ke_world_params);
    pb.ecs = &ecs_b.vtable;
    pb.runtime = &runtime;

    const ha = ke_world_create(&pa, null);
    const hb = ke_world_create(&pb, null);
    try testing.expect(ha.ref != null);
    try testing.expect(hb.ref != null);

    const wa = ha.ref.?;
    const wb = hb.ref.?;
    const ea = wa.*.ecs.?(wa).?;
    const eb = wb.*.ecs.?(wb).?;
    try testing.expect(ea != eb);

    const a = ea.*.entity_create.?(ea);
    const b = eb.*.entity_create.?(eb);
    try testing.expect(a != c.KE_ENTITY_INVALID);
    try testing.expect(b != c.KE_ENTITY_INVALID);

    ha.destroy.?(ha.ref);

    const b2 = eb.*.entity_create.?(eb);
    try testing.expect(b2 != c.KE_ENTITY_INVALID);
    try testing.expect(b2 != b);

    hb.destroy.?(hb.ref);
}

test "creating and destroying a world leaves no block allocated" {
    var ecs: StubEcs = undefined;
    stubEcsInit(&ecs);
    var runtime = std.mem.zeroes(c.ke_runtime);

    var params = std.mem.zeroes(c.ke_world_params);
    params.ecs = &ecs.vtable;
    params.runtime = &runtime;
    params.project_root = "res/";

    const h = ke_world_create(&params, null);
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}
