const std = @import("std");

const c = @import("c.zig").c;
const heap = @import("heap");

const E = @import("kerror").Errors(c);

const apply = @import("components_apply.zig");

const apply_initial_capacity: u32 = 16;

const ApplyEntry = struct {
    cid: c.ke_component_id,
    fn_ptr: c.ke_component_apply_fn,
    ctx: ?*anyopaque,
    fields: ?[*]const c.ke_component_field,
    field_count: u32,
};

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

const Block = struct {
    state: State,
    world: c.ke_world,
};

fn stateOf(self: *c.ke_world) *State {
    return @ptrCast(@alignCast(self.handle));
}

/// The logger the world was built with, for plugin-internal diagnostics.
pub fn loggerOf(self: *c.ke_world) ?*c.ke_logger {
    return stateOf(self).logger;
}

/// The signal bus the world was built with, for plugin-internal wiring.
pub fn signalBusOf(self: *c.ke_world) ?*c.ke_signal_bus {
    return stateOf(self).signal_bus;
}

fn worldEcs(self_in: ?*c.ke_world) callconv(.c) ?*c.ke_ecs {
    const self = self_in orelse return null;
    return stateOf(self).ecs;
}

fn worldRuntime(self_in: ?*c.ke_world) callconv(.c) ?*c.ke_runtime {
    const self = self_in orelse return null;
    return stateOf(self).runtime;
}

fn worldSceneTree(self_in: ?*c.ke_world) callconv(.c) ?*c.ke_scene_tree {
    const self = self_in orelse return null;
    return stateOf(self).scene_tree;
}

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

fn worldDestroy(self_in: ?*c.ke_world) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    if (s.apply_registry) |reg| heap.gpa.free(reg[0..s.apply_capacity]);
    heap.gpa.destroy(@as(*Block, @fieldParentPtr("state", s)));
    heap.release();
}

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

    heap.retain();
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
