//! The scene side of render: the set of its scene components, and the update-phase systems that
//! give a mesh, a sprite and a label the GPU resources and the font they name, behind one factory
//! each.

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
const R = @import("result").Result(abi_result, .{});
const component_apply = @import("component_apply.zig");
const mesh_resolve = @import("mesh_resolve.zig");
const sprite_resolve = @import("sprite_resolve.zig");
const label_resolve = @import("label_resolve.zig");

const heap = @import("heap");
const gpa = heap.gpa;

const Components = @import("scene_components").Set(&.{
    .{ .name = abi_render.KE_COMPONENT_NAME_MESH, .size = @sizeOf(abi_render.ke_mesh_component), .alignment = @alignOf(abi_render.ke_mesh_component), .fields = &abi_render.ke_mesh_component_fields, .apply = component_apply.ke_render_apply_mesh },
    .{ .name = abi_render.KE_COMPONENT_NAME_CAMERA, .size = @sizeOf(abi_render.ke_camera_component), .alignment = @alignOf(abi_render.ke_camera_component), .fields = &abi_render.ke_camera_component_fields, .apply = component_apply.ke_render_apply_camera },
    .{ .name = abi_render.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, .size = @sizeOf(abi_render.ke_directional_light_component), .alignment = @alignOf(abi_render.ke_directional_light_component), .fields = &abi_render.ke_directional_light_component_fields },
    .{ .name = abi_render.KE_COMPONENT_NAME_POINT_LIGHT, .size = @sizeOf(abi_render.ke_point_light_component), .alignment = @alignOf(abi_render.ke_point_light_component), .fields = &abi_render.ke_point_light_component_fields },
    .{ .name = abi_render.KE_COMPONENT_NAME_SPOT_LIGHT, .size = @sizeOf(abi_render.ke_spot_light_component), .alignment = @alignOf(abi_render.ke_spot_light_component), .fields = &abi_render.ke_spot_light_component_fields },
    .{ .name = abi_render.KE_COMPONENT_NAME_AMBIENT_LIGHT, .size = @sizeOf(abi_render.ke_ambient_light_component), .alignment = @alignOf(abi_render.ke_ambient_light_component), .fields = &abi_render.ke_ambient_light_component_fields },
    .{ .name = abi_render.KE_COMPONENT_NAME_SKYBOX, .size = @sizeOf(abi_render.ke_skybox_component), .alignment = @alignOf(abi_render.ke_skybox_component) },
    .{ .name = abi_render.KE_COMPONENT_NAME_SPRITE2D, .size = @sizeOf(abi_render.ke_sprite2d_component), .alignment = @alignOf(abi_render.ke_sprite2d_component), .fields = &abi_render.ke_sprite2d_component_fields, .apply = component_apply.ke_render_apply_sprite2d },
    .{ .name = abi_render.KE_COMPONENT_NAME_LABEL, .size = @sizeOf(abi_render.ke_label_component), .alignment = @alignOf(abi_render.ke_label_component), .fields = &abi_render.ke_label_component_fields },
});

/// The factory of the scene component set. The set holds no state, so it cannot fail.
export fn ke_render_scene_components_create() callconv(.c) abi_framework.ke_scene_component_set_handle {
    return Components.handle();
}

/// The state of one scene resolve. The factory allocates it and `destroyScene` frees it. The
/// runtime receives the core and `sprite` as the contexts of the two systems, and their queries
/// point into it, so it is not moved after creation.
const SceneResolve = struct {
    api: abi_render_scene_factory.ke_render_scene_resolve,
    ids: abi_render_scene_factory.ke_render_scene_component_ids,
    sprite: sprite_resolve.State,
    mesh_terms: [1]abi_runtime.ke_component_access,
    mesh_queries: [1]abi_runtime.ke_query_decl,
    sprite_terms: [3]abi_runtime.ke_component_access,
    sprite_queries: [2]abi_runtime.ke_query_decl,
};

const mesh_resolve_after = [_][*c]const u8{"render.sprite2d.resolve"};

/// The `component_ids` slot.
fn componentIds(self: [*c]abi_render_scene_factory.ke_render_scene_resolve) callconv(.c) [*c]const abi_render_scene_factory.ke_render_scene_component_ids {
    if (self == null) return null;
    const st: *SceneResolve = @ptrCast(@alignCast(self.*.handle));
    return &st.ids;
}

/// The `destroy` slot of the handle `ke_render_scene_resolve_create` returns; a null argument is
/// ignored.
fn destroyScene(self: ?*abi_render_scene_factory.ke_render_scene_resolve) callconv(.c) void {
    const s = self orelse return;
    const st: *SceneResolve = @ptrCast(@alignCast(s.handle));
    gpa.destroy(st);
}

/// Registers the component type with the ecs under its name, its size and its field table, and
/// returns the id the ecs gives it.
fn registerComponent(e: *abi_ecs.ke_ecs, name: [*c]const u8, comptime T: type, comptime table: anytype) R.Error!abi_ecs.ke_component_id {
    const fields = @typeInfo(@TypeOf(table.*)).array;
    var cid: abi_ecs.ke_component_id = abi_ecs.KE_COMPONENT_INVALID;
    try R.check(e.component_register.?(e, &abi_ecs.ke_component_params{ .name = name, .size = @sizeOf(T), .alignment = @alignOf(T), .fields = table, .field_count = @intCast(fields.len) }, &cid));
    return cid;
}

fn registerBare(e: *abi_ecs.ke_ecs, name: [*c]const u8, comptime T: type) R.Error!abi_ecs.ke_component_id {
    var cid: abi_ecs.ke_component_id = abi_ecs.KE_COMPONENT_INVALID;
    try R.check(e.component_register.?(e, &abi_ecs.ke_component_params{ .name = name, .size = @sizeOf(T), .alignment = @alignOf(T), .fields = null, .field_count = 0 }, &cid));
    return cid;
}

fn registerIds(e: *abi_ecs.ke_ecs, ids: *abi_render_scene_factory.ke_render_scene_component_ids) R.Error!void {
    ids.mesh = try registerComponent(e, abi_render.KE_COMPONENT_NAME_MESH, abi_render.ke_mesh_component, &abi_render.ke_mesh_component_fields);
    ids.world_transform = try registerBare(e, abi_spatial.KE_COMPONENT_NAME_WORLD_TRANSFORM, abi_spatial.ke_world_transform_component);
    ids.camera = try registerComponent(e, abi_render.KE_COMPONENT_NAME_CAMERA, abi_render.ke_camera_component, &abi_render.ke_camera_component_fields);
    ids.directional_light = try registerComponent(e, abi_render.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, abi_render.ke_directional_light_component, &abi_render.ke_directional_light_component_fields);
    ids.point_light = try registerComponent(e, abi_render.KE_COMPONENT_NAME_POINT_LIGHT, abi_render.ke_point_light_component, &abi_render.ke_point_light_component_fields);
    ids.spot_light = try registerComponent(e, abi_render.KE_COMPONENT_NAME_SPOT_LIGHT, abi_render.ke_spot_light_component, &abi_render.ke_spot_light_component_fields);
    ids.ambient_light = try registerComponent(e, abi_render.KE_COMPONENT_NAME_AMBIENT_LIGHT, abi_render.ke_ambient_light_component, &abi_render.ke_ambient_light_component_fields);
    ids.skybox = try registerBare(e, abi_render.KE_COMPONENT_NAME_SKYBOX, abi_render.ke_skybox_component);
    ids.sprite2d = try registerComponent(e, abi_render.KE_COMPONENT_NAME_SPRITE2D, abi_render.ke_sprite2d_component, &abi_render.ke_sprite2d_component_fields);
    ids.label = try registerComponent(e, abi_render.KE_COMPONENT_NAME_LABEL, abi_render.ke_label_component, &abi_render.ke_label_component_fields);
}

/// The factory declared in scene_resolve_create.h. A missing runtime, ecs or service fails as an
/// invalid argument, a failed allocation as out of memory and a component the ecs refuses with the
/// ecs's code. The runtime refusing either system fails with its code, removes the sprite system
/// when it was the mesh system that was refused, and leaves the handle zeroed.
export fn ke_render_scene_resolve_create(params_in: ?*const abi_render_scene_factory.ke_render_scene_resolve_params, out_resolve: [*c]abi_render_scene_factory.ke_render_scene_resolve_handle) callconv(.c) abi_result.ke_result {
    const out = out_resolve orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const p = params_in orelse return R.code(error.InvalidArgument);
    const rt: *abi_runtime.ke_runtime = p.runtime orelse return R.code(error.InvalidArgument);
    const e: *abi_ecs.ke_ecs = p.ecs orelse return R.code(error.InvalidArgument);
    const core = p.service orelse return R.code(error.InvalidArgument);

    const st = gpa.create(SceneResolve) catch |err| return R.code(err);
    registerScene(st, p, rt, e, core) catch |err| {
        gpa.destroy(st);
        return R.code(err);
    };
    out.* = .{ .ref = &st.api, .destroy = destroyScene };
    return R.ok;
}

fn registerScene(st: *SceneResolve, p: *const abi_render_scene_factory.ke_render_scene_resolve_params, rt: *abi_runtime.ke_runtime, e: *abi_ecs.ke_ecs, core: *abi_render.ke_render_service) R.Error!void {
    st.api = .{ .handle = st, .component_ids = componentIds };
    try registerIds(e, &st.ids);

    st.sprite = .{ .core = core, .mesh_cid = st.ids.mesh, .resolver = p.resolver };
    st.sprite_terms = .{ .{ .cid = st.ids.sprite2d, .access = abi_runtime.KE_ACCESS_WRITE }, .{ .cid = st.ids.mesh, .access = abi_runtime.KE_ACCESS_WRITE }, .{ .cid = st.ids.sprite2d, .access = abi_runtime.KE_ACCESS_WRITE } };
    st.sprite_queries = .{ .{ .terms = st.sprite_terms[0..].ptr, .term_count = 2 }, .{ .terms = st.sprite_terms[2..].ptr, .term_count = 1 } };
    var sprite = std.mem.zeroes(abi_runtime.ke_runtime_system_params);
    sprite.name = "render.sprite2d.resolve";
    sprite.phase = abi_runtime.KE_PHASE_UPDATE;
    sprite.queries = &st.sprite_queries;
    sprite.query_count = st.sprite_queries.len;
    sprite.pinned_thread = 0;
    sprite.user_data = &st.sprite;
    sprite.execute = sprite_resolve.system;
    var sprite_id: abi_runtime.ke_system_id = 0;
    try R.check(rt.register_system.?(rt, &sprite, &sprite_id));
    errdefer _ = rt.unregister_system.?(rt, sprite_id);

    st.mesh_terms = .{.{ .cid = st.ids.mesh, .access = abi_runtime.KE_ACCESS_WRITE }};
    st.mesh_queries = .{.{ .terms = st.mesh_terms[0..].ptr, .term_count = 1 }};
    var mesh = std.mem.zeroes(abi_runtime.ke_runtime_system_params);
    mesh.name = "render.mesh.resolve";
    mesh.phase = abi_runtime.KE_PHASE_UPDATE;
    mesh.queries = &st.mesh_queries;
    mesh.query_count = st.mesh_queries.len;
    mesh.pinned_thread = 0;
    mesh.user_data = core;
    mesh.execute = mesh_resolve.system;
    mesh.after = &mesh_resolve_after;
    mesh.after_count = mesh_resolve_after.len;
    var system_id: abi_runtime.ke_system_id = 0;
    try R.check(rt.register_system.?(rt, &mesh, &system_id));
}

/// The state of one label resolve. The factory allocates it and `destroyLabel` frees it. The
/// runtime receives `state` as the context of the system, and its query points into it, so it is
/// not moved after creation.
const LabelResolve = struct {
    state: label_resolve.State,
    terms: [1]abi_runtime.ke_component_access,
    queries: [1]abi_runtime.ke_query_decl,
};

const label_resolve_before = [_][*c]const u8{"render.ui.labels"};

/// The `destroy` slot of the handle `ke_render_label_resolve_create` returns; a null argument is
/// ignored.
fn destroyLabel(self: ?*abi_render_scene_factory.ke_render_label_resolve) callconv(.c) void {
    const st: *LabelResolve = @ptrCast(@alignCast(self orelse return));
    gpa.destroy(st);
}

/// The factory declared in label_resolve_create.h. A missing runtime, service or ui fails as an
/// invalid argument, a failed allocation as out of memory, and the runtime refusing the system
/// with the runtime's code.
export fn ke_render_label_resolve_create(params_in: ?*const abi_render_scene_factory.ke_render_label_resolve_params, out_resolve: [*c]abi_render_scene_factory.ke_render_label_resolve_handle) callconv(.c) abi_result.ke_result {
    const out = out_resolve orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const p = params_in orelse return R.code(error.InvalidArgument);
    const rt: *abi_runtime.ke_runtime = p.runtime orelse return R.code(error.InvalidArgument);
    const core = p.service orelse return R.code(error.InvalidArgument);
    const ui = p.ui orelse return R.code(error.InvalidArgument);

    const st = gpa.create(LabelResolve) catch |err| return R.code(err);
    st.state = .{ .core = core, .ui = ui, .resolver = p.resolver };
    st.terms = .{.{ .cid = p.label_cid, .access = abi_runtime.KE_ACCESS_WRITE }};
    st.queries = .{.{ .terms = st.terms[0..].ptr, .term_count = 1 }};
    var label = std.mem.zeroes(abi_runtime.ke_runtime_system_params);
    label.name = "render.label.resolve";
    label.phase = abi_runtime.KE_PHASE_UPDATE;
    label.queries = &st.queries;
    label.query_count = st.queries.len;
    label.pinned_thread = 0;
    label.user_data = &st.state;
    label.execute = label_resolve.system;
    label.before = &label_resolve_before;
    label.before_count = label_resolve_before.len;
    var system_id: abi_runtime.ke_system_id = 0;
    const registered = rt.register_system.?(rt, &label, &system_id);
    if (registered != R.ok) {
        gpa.destroy(st);
        return registered;
    }
    out.* = .{ .ref = @ptrCast(st), .destroy = destroyLabel };
    return R.ok;
}

const testing = std.testing;

const Stubs = @import("stubs");

const Rig = struct {
    dev: Stubs.Device,
    core: Stubs.Core,
    rt: Stubs.Runtime,
    ecs: Stubs.Ecs,

    fn init(self: *Rig) void {
        self.dev.init();
        self.core.init(self.dev.api());
        self.rt.init();
        self.ecs.init();
    }

    fn sceneParams(self: *Rig) abi_render_scene_factory.ke_render_scene_resolve_params {
        return .{ .runtime = self.rt.api(), .ecs = self.ecs.api(), .service = self.core.api(), .resolver = null };
    }
};

test "the scene resolve registers both its systems and hands out an id for every component" {
    var rig: Rig = undefined;
    rig.init();
    var h: abi_render_scene_factory.ke_render_scene_resolve_handle = undefined;
    try R.check(ke_render_scene_resolve_create(&rig.sceneParams(), &h));
    try testing.expectEqual(@as(u32, 2), rig.rt.live_count);
    const ids = h.ref.?.component_ids.?(h.ref);
    inline for (@typeInfo(abi_render_scene_factory.ke_render_scene_component_ids).@"struct".fields) |f| {
        try testing.expect(@field(ids.?, f.name) != abi_ecs.KE_COMPONENT_INVALID);
    }
    h.destroy.?(h.ref);
}

test "a scene resolve whose mesh system the runtime refuses removes its sprite system and fails" {
    var rig: Rig = undefined;
    rig.init();
    rig.rt.limit = 1;
    var h: abi_render_scene_factory.ke_render_scene_resolve_handle = undefined;
    try testing.expect(ke_render_scene_resolve_create(&rig.sceneParams(), &h) != R.ok);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(u32, 0), rig.rt.live_count);
}

test "a scene resolve missing its service is refused as an invalid argument" {
    var rig: Rig = undefined;
    rig.init();
    var p = rig.sceneParams();
    p.service = null;
    var h: abi_render_scene_factory.ke_render_scene_resolve_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_scene_resolve_create(&p, &h)));
    try testing.expect(h.ref == null);
}

test "the label resolve registers its system, and fails when the runtime refuses it" {
    var rig: Rig = undefined;
    rig.init();
    var ui = std.mem.zeroes(abi_render_ui_factory.ke_render_ui);
    const p = abi_render_scene_factory.ke_render_label_resolve_params{ .runtime = rig.rt.api(), .service = rig.core.api(), .ui = &ui, .resolver = null, .label_cid = 7 };
    var h: abi_render_scene_factory.ke_render_label_resolve_handle = undefined;
    try R.check(ke_render_label_resolve_create(&p, &h));
    try testing.expectEqual(@as(u32, 1), rig.rt.live_count);
    h.destroy.?(h.ref);

    rig.rt.limit = rig.rt.registered;
    try testing.expect(ke_render_label_resolve_create(&p, &h) != R.ok);
    try testing.expect(h.ref == null);
}

test "a label resolve missing its ui is refused as an invalid argument" {
    var rig: Rig = undefined;
    rig.init();
    const p = abi_render_scene_factory.ke_render_label_resolve_params{ .runtime = rig.rt.api(), .service = rig.core.api(), .ui = null, .resolver = null, .label_cid = 7 };
    var h: abi_render_scene_factory.ke_render_label_resolve_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_label_resolve_create(&p, &h)));
    try testing.expect(h.ref == null);
}

test "creating and destroying the scene resolve and the label resolve leaves no block allocated" {
    try heap.expectNoLeaks();
}
