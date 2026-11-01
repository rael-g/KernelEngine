//! The scene side of render: the set of its scene components, and the update-phase systems that
//! give a mesh, a sprite and a label the GPU resources and the font they name, behind one factory
//! each.

const abi_render_contract = @import("abi_render_contract");
const abi_spatial_contract = @import("abi_spatial_contract");
const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_components = @import("abi_render_components");
const abi_scene_loader = @import("abi_scene_loader");
const abi_ui_components = @import("abi_ui_components");
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_scene").logFn };

pub const abi_ecs = @import("abi_ecs");
const abi_framework = @import("abi_framework");
const abi_render = @import("abi_render");
const abi_render_scene_factory = @import("abi_render_scene_factory");
const abi_render_ui_factory = @import("abi_render_ui_factory");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const abi_spatial = @import("abi_spatial");
const R = @import("result").Result(.{});
const component_apply = @import("component_apply.zig");
const mesh_resolve = @import("mesh_resolve.zig");
const sprite_resolve = @import("sprite_resolve.zig");
const label_resolve = @import("label_resolve.zig");

const heap = @import("heap");
const gpa = heap.gpa;

const Component = struct {
    component: abi_ecs.c.ke_component_params,
    apply: abi_framework.c.ke_component_apply_fn,
};

const components = [_]Component{
    .{ .component = .{ .name = abi_render_contract.c.KE_COMPONENT_NAME_MESH, .size = @sizeOf(abi_render_components.c.ke_mesh_component), .alignment = @alignOf(abi_render_components.c.ke_mesh_component), .fields = &abi_render_contract.c.ke_mesh_component_fields, .field_count = abi_render_contract.c.ke_mesh_component_fields.len }, .apply = component_apply.ke_render_apply_mesh },
    .{ .component = .{ .name = abi_render_contract.c.KE_COMPONENT_NAME_CAMERA, .size = @sizeOf(abi_render_components.c.ke_camera_component), .alignment = @alignOf(abi_render_components.c.ke_camera_component), .fields = &abi_render_contract.c.ke_camera_component_fields, .field_count = abi_render_contract.c.ke_camera_component_fields.len }, .apply = component_apply.ke_render_apply_camera },
    .{ .component = .{ .name = abi_render_contract.c.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, .size = @sizeOf(abi_render_components.c.ke_directional_light_component), .alignment = @alignOf(abi_render_components.c.ke_directional_light_component), .fields = &abi_render_contract.c.ke_directional_light_component_fields, .field_count = abi_render_contract.c.ke_directional_light_component_fields.len }, .apply = null },
    .{ .component = .{ .name = abi_render_contract.c.KE_COMPONENT_NAME_POINT_LIGHT, .size = @sizeOf(abi_render_components.c.ke_point_light_component), .alignment = @alignOf(abi_render_components.c.ke_point_light_component), .fields = &abi_render_contract.c.ke_point_light_component_fields, .field_count = abi_render_contract.c.ke_point_light_component_fields.len }, .apply = null },
    .{ .component = .{ .name = abi_render_contract.c.KE_COMPONENT_NAME_SPOT_LIGHT, .size = @sizeOf(abi_render_components.c.ke_spot_light_component), .alignment = @alignOf(abi_render_components.c.ke_spot_light_component), .fields = &abi_render_contract.c.ke_spot_light_component_fields, .field_count = abi_render_contract.c.ke_spot_light_component_fields.len }, .apply = null },
    .{ .component = .{ .name = abi_render_contract.c.KE_COMPONENT_NAME_AMBIENT_LIGHT, .size = @sizeOf(abi_render_components.c.ke_ambient_light_component), .alignment = @alignOf(abi_render_components.c.ke_ambient_light_component), .fields = &abi_render_contract.c.ke_ambient_light_component_fields, .field_count = abi_render_contract.c.ke_ambient_light_component_fields.len }, .apply = null },
    .{ .component = .{ .name = abi_render_contract.c.KE_COMPONENT_NAME_SKYBOX, .size = @sizeOf(abi_render_components.c.ke_skybox_component), .alignment = @alignOf(abi_render_components.c.ke_skybox_component) }, .apply = null },
    .{ .component = .{ .name = abi_render_contract.c.KE_COMPONENT_NAME_SPRITE2D, .size = @sizeOf(abi_render_components.c.ke_sprite2d_component), .alignment = @alignOf(abi_render_components.c.ke_sprite2d_component), .fields = &abi_render_contract.c.ke_sprite2d_component_fields, .field_count = abi_render_contract.c.ke_sprite2d_component_fields.len }, .apply = component_apply.ke_render_apply_sprite2d },
    .{ .component = .{ .name = abi_render_contract.c.KE_COMPONENT_NAME_LABEL, .size = @sizeOf(abi_ui_components.c.ke_label_component), .alignment = @alignOf(abi_ui_components.c.ke_label_component), .fields = &abi_render_contract.c.ke_label_component_fields, .field_count = abi_render_contract.c.ke_label_component_fields.len }, .apply = null },
};

/// The factory of the scene components. Adds them in order and stops at the first one the set
/// refuses.
export fn ke_render_scene_components_create(set_in: ?*abi_framework.c.ke_scene_component_set) callconv(.c) abi_result.c.ke_result {
    const set = set_in orelse return R.code(error.InvalidArgument);
    for (&components) |*c| {
        const added = set.add.?(set, &c.component, c.apply);
        if (added != R.ok) return added;
    }
    return R.ok;
}

/// The state of one scene resolve. The factory allocates it and `destroyScene` frees it. The
/// runtime receives the core and `sprite` as the contexts of the two systems, and their queries
/// point into it, so it is not moved after creation. `destroyScene` unregisters both systems
/// before it frees the resolve.
const SceneResolve = struct {
    api: abi_render.c.ke_render_scene_resolve,
    runtime: *abi_runtime.c.ke_runtime,
    systems: [2]abi_framework.c.ke_system_id,
    ids: abi_render.c.ke_render_scene_component_ids,
    sprite: sprite_resolve.State,
    mesh_terms: [1]abi_runtime.c.ke_component_access,
    mesh_queries: [1]abi_runtime.c.ke_query_decl,
    sprite_terms: [3]abi_runtime.c.ke_component_access,
    sprite_queries: [2]abi_runtime.c.ke_query_decl,
};

const mesh_resolve_after = [_][*c]const u8{"render.sprite2d.resolve"};

/// The `component_ids` slot.
fn componentIds(self: [*c]abi_render.c.ke_render_scene_resolve) callconv(.c) [*c]const abi_render.c.ke_render_scene_component_ids {
    if (self == null) return null;
    const st: *SceneResolve = @ptrCast(@alignCast(self.*.handle));
    return &st.ids;
}

/// The `destroy` slot of the handle `ke_render_scene_resolve_create` returns; a null argument is
/// ignored.
fn destroyScene(self: ?*abi_render.c.ke_render_scene_resolve) callconv(.c) void {
    const s = self orelse return;
    const st: *SceneResolve = @ptrCast(@alignCast(s.handle));
    for (st.systems) |id| _ = st.runtime.unregister_system.?(st.runtime, id);
    gpa.destroy(st);
}

/// Registers the component type with the ecs under its name, its size and its field table, and
/// returns the id the ecs gives it.
fn registerComponent(e: *abi_ecs.c.ke_ecs, name: [*c]const u8, comptime T: type, comptime table: anytype) R.Error!abi_asset_resolver.c.ke_component_id {
    const fields = @typeInfo(@TypeOf(table.*)).array;
    var cid: abi_asset_resolver.c.ke_component_id = abi_ecs.c.KE_COMPONENT_INVALID;
    try R.check(e.component_register.?(e, &abi_ecs.c.ke_component_params{ .name = name, .size = @sizeOf(T), .alignment = @alignOf(T), .fields = table, .field_count = @intCast(fields.len) }, &cid));
    return cid;
}

fn registerBare(e: *abi_ecs.c.ke_ecs, name: [*c]const u8, comptime T: type) R.Error!abi_asset_resolver.c.ke_component_id {
    var cid: abi_asset_resolver.c.ke_component_id = abi_ecs.c.KE_COMPONENT_INVALID;
    try R.check(e.component_register.?(e, &abi_ecs.c.ke_component_params{ .name = name, .size = @sizeOf(T), .alignment = @alignOf(T), .fields = null, .field_count = 0 }, &cid));
    return cid;
}

fn registerIds(e: *abi_ecs.c.ke_ecs, ids: *abi_render.c.ke_render_scene_component_ids) R.Error!void {
    ids.mesh = try registerComponent(e, abi_render_contract.c.KE_COMPONENT_NAME_MESH, abi_render_components.c.ke_mesh_component, &abi_render_contract.c.ke_mesh_component_fields);
    ids.world_transform = try registerBare(e, abi_spatial_contract.c.KE_COMPONENT_NAME_WORLD_TRANSFORM, abi_spatial.c.ke_world_transform_component);
    ids.camera = try registerComponent(e, abi_render_contract.c.KE_COMPONENT_NAME_CAMERA, abi_render_components.c.ke_camera_component, &abi_render_contract.c.ke_camera_component_fields);
    ids.directional_light = try registerComponent(e, abi_render_contract.c.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, abi_render_components.c.ke_directional_light_component, &abi_render_contract.c.ke_directional_light_component_fields);
    ids.point_light = try registerComponent(e, abi_render_contract.c.KE_COMPONENT_NAME_POINT_LIGHT, abi_render_components.c.ke_point_light_component, &abi_render_contract.c.ke_point_light_component_fields);
    ids.spot_light = try registerComponent(e, abi_render_contract.c.KE_COMPONENT_NAME_SPOT_LIGHT, abi_render_components.c.ke_spot_light_component, &abi_render_contract.c.ke_spot_light_component_fields);
    ids.ambient_light = try registerComponent(e, abi_render_contract.c.KE_COMPONENT_NAME_AMBIENT_LIGHT, abi_render_components.c.ke_ambient_light_component, &abi_render_contract.c.ke_ambient_light_component_fields);
    ids.skybox = try registerBare(e, abi_render_contract.c.KE_COMPONENT_NAME_SKYBOX, abi_render_components.c.ke_skybox_component);
    ids.sprite2d = try registerComponent(e, abi_render_contract.c.KE_COMPONENT_NAME_SPRITE2D, abi_render_components.c.ke_sprite2d_component, &abi_render_contract.c.ke_sprite2d_component_fields);
    ids.label = try registerComponent(e, abi_render_contract.c.KE_COMPONENT_NAME_LABEL, abi_ui_components.c.ke_label_component, &abi_render_contract.c.ke_label_component_fields);
}

/// The factory declared in scene_resolve_create.h. A missing runtime, ecs or service fails as an
/// invalid argument, a failed allocation as out of memory and a component the ecs refuses with the
/// ecs's code. The runtime refusing either system fails with its code, removes the sprite system
/// when it was the mesh system that was refused, and leaves the handle zeroed.
export fn ke_render_scene_resolve_create(params_in: ?*const abi_render_scene_factory.c.ke_render_scene_resolve_params, out_resolve: [*c]abi_render.c.ke_render_scene_resolve_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_resolve orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const p = params_in orelse return R.code(error.InvalidArgument);
    const rt: *abi_runtime.c.ke_runtime = p.runtime orelse return R.code(error.InvalidArgument);
    const e: *abi_ecs.c.ke_ecs = p.ecs orelse return R.code(error.InvalidArgument);
    const core = p.service orelse return R.code(error.InvalidArgument);

    const st = gpa.create(SceneResolve) catch |err| return R.code(err);
    registerScene(st, p, rt, e, core) catch |err| {
        gpa.destroy(st);
        return R.code(err);
    };
    out.* = .{ .ref = &st.api, .destroy = destroyScene };
    return R.ok;
}

fn registerScene(st: *SceneResolve, p: *const abi_render_scene_factory.c.ke_render_scene_resolve_params, rt: *abi_runtime.c.ke_runtime, e: *abi_ecs.c.ke_ecs, core: *abi_render.c.ke_render_service) R.Error!void {
    st.api = .{ .handle = st, .component_ids = componentIds };
    try registerIds(e, &st.ids);

    st.sprite = .{ .core = core, .mesh_cid = st.ids.mesh, .resolver = p.resolver };
    st.sprite_terms = .{ .{ .cid = st.ids.sprite2d, .access = abi_runtime.c.KE_ACCESS_WRITE }, .{ .cid = st.ids.mesh, .access = abi_runtime.c.KE_ACCESS_WRITE }, .{ .cid = st.ids.sprite2d, .access = abi_runtime.c.KE_ACCESS_WRITE } };
    st.sprite_queries = .{ .{ .terms = st.sprite_terms[0..].ptr, .term_count = 2 }, .{ .terms = st.sprite_terms[2..].ptr, .term_count = 1 } };
    var sprite = std.mem.zeroes(abi_runtime.c.ke_runtime_system_params);
    sprite.name = "render.sprite2d.resolve";
    sprite.phase = abi_runtime.c.KE_PHASE_UPDATE;
    sprite.queries = &st.sprite_queries;
    sprite.query_count = st.sprite_queries.len;
    sprite.user_data = &st.sprite;
    sprite.execute = sprite_resolve.system;
    var sprite_id: abi_framework.c.ke_system_id = 0;
    try R.check(rt.register_system.?(rt, &sprite, &sprite_id));
    errdefer _ = rt.unregister_system.?(rt, sprite_id);

    st.mesh_terms = .{.{ .cid = st.ids.mesh, .access = abi_runtime.c.KE_ACCESS_WRITE }};
    st.mesh_queries = .{.{ .terms = st.mesh_terms[0..].ptr, .term_count = 1 }};
    var mesh = std.mem.zeroes(abi_runtime.c.ke_runtime_system_params);
    mesh.name = "render.mesh.resolve";
    mesh.phase = abi_runtime.c.KE_PHASE_UPDATE;
    mesh.queries = &st.mesh_queries;
    mesh.query_count = st.mesh_queries.len;
    mesh.user_data = core;
    mesh.execute = mesh_resolve.system;
    mesh.after = &mesh_resolve_after;
    mesh.after_count = mesh_resolve_after.len;
    var system_id: abi_framework.c.ke_system_id = 0;
    try R.check(rt.register_system.?(rt, &mesh, &system_id));
    st.runtime = rt;
    st.systems = .{ sprite_id, system_id };
}

/// The state of one label resolve. The factory allocates it and `destroyLabel` frees it. The
/// runtime receives `state` as the context of the system, and its query points into it, so it is
/// not moved after creation. `destroyLabel` unregisters the system before it frees the resolve.
const LabelResolve = struct {
    state: label_resolve.State,
    runtime: *abi_runtime.c.ke_runtime,
    system: abi_framework.c.ke_system_id,
    terms: [1]abi_runtime.c.ke_component_access,
    queries: [1]abi_runtime.c.ke_query_decl,
};

const label_resolve_before = [_][*c]const u8{"render.ui.labels"};

/// The `destroy` slot of the handle `ke_render_label_resolve_create` returns; a null argument is
/// ignored.
fn destroyLabel(self: ?*abi_render_scene_factory.c.ke_render_label_resolve) callconv(.c) void {
    const st: *LabelResolve = @ptrCast(@alignCast(self orelse return));
    _ = st.runtime.unregister_system.?(st.runtime, st.system);
    gpa.destroy(st);
}

/// The factory declared in label_resolve_create.h. A missing runtime, service or ui fails as an
/// invalid argument, a failed allocation as out of memory, and the runtime refusing the system
/// with the runtime's code.
export fn ke_render_label_resolve_create(params_in: ?*const abi_render_scene_factory.c.ke_render_label_resolve_params, out_resolve: [*c]abi_render_scene_factory.c.ke_render_label_resolve_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_resolve orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const p = params_in orelse return R.code(error.InvalidArgument);
    const rt: *abi_runtime.c.ke_runtime = p.runtime orelse return R.code(error.InvalidArgument);
    const core = p.service orelse return R.code(error.InvalidArgument);
    const ui = p.ui orelse return R.code(error.InvalidArgument);

    const st = gpa.create(LabelResolve) catch |err| return R.code(err);
    st.state = .{ .core = core, .ui = ui, .resolver = p.resolver };
    st.terms = .{.{ .cid = p.label_cid, .access = abi_runtime.c.KE_ACCESS_WRITE }};
    st.queries = .{.{ .terms = st.terms[0..].ptr, .term_count = 1 }};
    var label = std.mem.zeroes(abi_runtime.c.ke_runtime_system_params);
    label.name = "render.label.resolve";
    label.phase = abi_runtime.c.KE_PHASE_UPDATE;
    label.queries = &st.queries;
    label.query_count = st.queries.len;
    label.user_data = &st.state;
    label.execute = label_resolve.system;
    label.before = &label_resolve_before;
    label.before_count = label_resolve_before.len;
    var system_id: abi_framework.c.ke_system_id = 0;
    const registered = rt.register_system.?(rt, &label, &system_id);
    if (registered != R.ok) {
        gpa.destroy(st);
        return registered;
    }
    st.runtime = rt;
    st.system = system_id;
    out.* = .{ .ref = @ptrCast(st), .destroy = destroyLabel };
    return R.ok;
}

const testing = std.testing;

const zsub = @import("zsub");

const Rig = struct {
    core: zsub.For(abi_render.c.ke_render_service),
    rt: zsub.For(abi_runtime.c.ke_runtime),
    ecs: zsub.For(abi_ecs.c.ke_ecs),

    fn init(self: *Rig) !void {
        try self.core.init();
        _ = self.core.when(.cid).returnsFresh();
        try self.rt.init();
        _ = self.rt.when(.register_system).writesFresh(2);
        try self.ecs.init();
        _ = self.ecs.when(.component_register).writesFresh(2);
    }

    fn deinit(self: *Rig) void {
        self.ecs.deinit();
        self.rt.deinit();
        self.core.deinit();
    }

    fn sceneParams(self: *Rig) abi_render_scene_factory.c.ke_render_scene_resolve_params {
        return .{ .runtime = self.rt.api(), .ecs = self.ecs.api(), .service = self.core.api(), .resolver = null };
    }
};

test "the scene resolve registers both its systems and hands out an id for every component" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_render.c.ke_render_scene_resolve_handle = undefined;
    try R.check(ke_render_scene_resolve_create(&rig.sceneParams(), &h));
    try rig.rt.received(.register_system).times(2);
    try rig.rt.received(.unregister_system).never();
    const ids = h.ref.?.component_ids.?(h.ref);
    inline for (@typeInfo(abi_render.c.ke_render_scene_component_ids).@"struct".fields) |f| {
        try testing.expect(@field(ids.?, f.name) != abi_ecs.c.KE_COMPONENT_INVALID);
    }
    h.destroy.?(h.ref);
}

test "destroying the scene resolve unregisters both its systems" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_render.c.ke_render_scene_resolve_handle = undefined;
    try R.check(ke_render_scene_resolve_create(&rig.sceneParams(), &h));
    h.destroy.?(h.ref);
    try rig.rt.received(.register_system).atLeast(1);
    try rig.rt.received(.unregister_system).where(zsub.argIs(1, @as(abi_framework.c.ke_system_id, 0))).never();
    try rig.rt.received(.unregister_system).sameAs(rig.rt.received(.register_system));
}

test "a scene resolve whose mesh system the runtime refuses removes its sprite system and fails" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.rt.when(.register_system).returnsSeq(&.{ abi_result.c.KE_OK, abi_result.c.KE_RESULT_OUT_OF_MEMORY });
    var h: abi_render.c.ke_render_scene_resolve_handle = undefined;
    try testing.expect(ke_render_scene_resolve_create(&rig.sceneParams(), &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.rt.received(.unregister_system).times(1);
}

test "a scene resolve missing its service is refused as an invalid argument" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var p = rig.sceneParams();
    p.service = null;
    var h: abi_render.c.ke_render_scene_resolve_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_scene_resolve_create(&p, &h)));
    try testing.expect(h.ref == null);
}

test "the label resolve registers its system, and fails when the runtime refuses it" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var ui = std.mem.zeroes(abi_render_ui_factory.c.ke_render_ui);
    const p = abi_render_scene_factory.c.ke_render_label_resolve_params{ .runtime = rig.rt.api(), .service = rig.core.api(), .ui = &ui, .resolver = null, .label_cid = 7 };
    var h: abi_render_scene_factory.c.ke_render_label_resolve_handle = undefined;
    try R.check(ke_render_label_resolve_create(&p, &h));
    try rig.rt.received(.register_system).times(1);
    h.destroy.?(h.ref);

    _ = rig.rt.when(.register_system).returns(abi_result.c.KE_RESULT_OUT_OF_MEMORY);
    try testing.expect(ke_render_label_resolve_create(&p, &h) != R.ok);
    try testing.expect(h.ref == null);
}

test "destroying the label resolve unregisters its system" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var ui = std.mem.zeroes(abi_render_ui_factory.c.ke_render_ui);
    const p = abi_render_scene_factory.c.ke_render_label_resolve_params{ .runtime = rig.rt.api(), .service = rig.core.api(), .ui = &ui, .resolver = null, .label_cid = 7 };
    var h: abi_render_scene_factory.c.ke_render_label_resolve_handle = undefined;
    try R.check(ke_render_label_resolve_create(&p, &h));
    h.destroy.?(h.ref);
    try rig.rt.received(.register_system).atLeast(1);
    try rig.rt.received(.unregister_system).where(zsub.argIs(1, @as(abi_framework.c.ke_system_id, 0))).never();
    try rig.rt.received(.unregister_system).sameAs(rig.rt.received(.register_system));
}

test "a label resolve missing its ui is refused as an invalid argument" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const p = abi_render_scene_factory.c.ke_render_label_resolve_params{ .runtime = rig.rt.api(), .service = rig.core.api(), .ui = null, .resolver = null, .label_cid = 7 };
    var h: abi_render_scene_factory.c.ke_render_label_resolve_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_label_resolve_create(&p, &h)));
    try testing.expect(h.ref == null);
}

test "creating and destroying the scene resolve and the label resolve leaves no block allocated" {
    try heap.expectNoLeaks();
}
