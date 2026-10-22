//! The scene side of render: the set of its scene components, and the update-phase systems that
//! give a mesh, a sprite and a label the GPU resources and the font they name, behind one factory
//! each.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };
pub const c = @import("c");
const component_apply = @import("component_apply.zig");
const mesh_resolve = @import("mesh_resolve.zig");
const sprite_resolve = @import("sprite_resolve.zig");
const label_resolve = @import("label_resolve.zig");

const heap = @import("heap");
const gpa = heap.gpa;

const Components = @import("scene_components").Set(c, &.{
    .{ .name = c.KE_COMPONENT_NAME_MESH, .size = @sizeOf(c.ke_mesh_component), .alignment = @alignOf(c.ke_mesh_component), .fields = &c.ke_mesh_component_fields, .apply = component_apply.ke_render_apply_mesh },
    .{ .name = c.KE_COMPONENT_NAME_CAMERA, .size = @sizeOf(c.ke_camera_component), .alignment = @alignOf(c.ke_camera_component), .fields = &c.ke_camera_component_fields, .apply = component_apply.ke_render_apply_camera },
    .{ .name = c.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, .size = @sizeOf(c.ke_directional_light_component), .alignment = @alignOf(c.ke_directional_light_component), .fields = &c.ke_directional_light_component_fields },
    .{ .name = c.KE_COMPONENT_NAME_POINT_LIGHT, .size = @sizeOf(c.ke_point_light_component), .alignment = @alignOf(c.ke_point_light_component), .fields = &c.ke_point_light_component_fields },
    .{ .name = c.KE_COMPONENT_NAME_SPOT_LIGHT, .size = @sizeOf(c.ke_spot_light_component), .alignment = @alignOf(c.ke_spot_light_component), .fields = &c.ke_spot_light_component_fields },
    .{ .name = c.KE_COMPONENT_NAME_AMBIENT_LIGHT, .size = @sizeOf(c.ke_ambient_light_component), .alignment = @alignOf(c.ke_ambient_light_component), .fields = &c.ke_ambient_light_component_fields },
    .{ .name = c.KE_COMPONENT_NAME_SKYBOX, .size = @sizeOf(c.ke_skybox_component), .alignment = @alignOf(c.ke_skybox_component) },
    .{ .name = c.KE_COMPONENT_NAME_SPRITE2D, .size = @sizeOf(c.ke_sprite2d_component), .alignment = @alignOf(c.ke_sprite2d_component), .fields = &c.ke_sprite2d_component_fields, .apply = component_apply.ke_render_apply_sprite2d },
    .{ .name = c.KE_COMPONENT_NAME_LABEL, .size = @sizeOf(c.ke_label_component), .alignment = @alignOf(c.ke_label_component), .fields = &c.ke_label_component_fields },
});

/// The factory of the scene component set. The set holds no state, so it cannot fail.
export fn ke_render_scene_components_create() callconv(.c) c.ke_scene_component_set_handle {
    return Components.handle();
}

/// The state of one scene resolve. The factory allocates it and `destroyScene` frees it. The
/// runtime receives the core and `sprite` as the contexts of the two systems, and their queries
/// point into it, so it is not moved after creation.
const SceneResolve = struct {
    api: c.ke_render_scene_resolve,
    ids: c.ke_render_scene_component_ids,
    sprite: sprite_resolve.State,
    mesh_terms: [1]c.ke_component_access,
    mesh_queries: [1]c.ke_query_decl,
    sprite_terms: [3]c.ke_component_access,
    sprite_queries: [2]c.ke_query_decl,
};

const mesh_resolve_after = [_][*c]const u8{"render.sprite2d.resolve"};

/// The `component_ids` slot.
fn componentIds(self: [*c]c.ke_render_scene_resolve) callconv(.c) [*c]const c.ke_render_scene_component_ids {
    if (self == null) return null;
    const st: *SceneResolve = @ptrCast(@alignCast(self.*.handle));
    return &st.ids;
}

/// The `destroy` slot of the handle `ke_render_scene_resolve_create` returns; a null argument is
/// ignored.
fn destroyScene(self: ?*c.ke_render_scene_resolve) callconv(.c) void {
    const s = self orelse return;
    const st: *SceneResolve = @ptrCast(@alignCast(s.handle));
    gpa.destroy(st);
}

/// Registers the component type with the ecs under its name, its size and its field table, and
/// returns the id the ecs gives it.
fn registerComponent(e: *c.ke_ecs, name: [*c]const u8, comptime T: type, comptime table: anytype, out_error: [*c][*c]c.ke_error) c.ke_component_id {
    const fields = @typeInfo(@TypeOf(table.*)).array;
    return e.component_register.?(e, &c.ke_component_params{ .name = name, .size = @sizeOf(T), .alignment = @alignOf(T), .fields = table, .field_count = @intCast(fields.len) }, out_error);
}

fn registerIds(e: *c.ke_ecs, ids: *c.ke_render_scene_component_ids, out_error: [*c][*c]c.ke_error) bool {
    ids.mesh = registerComponent(e, c.KE_COMPONENT_NAME_MESH, c.ke_mesh_component, &c.ke_mesh_component_fields, out_error);
    ids.world_transform = e.component_register.?(e, &c.ke_component_params{ .name = c.KE_COMPONENT_NAME_WORLD_TRANSFORM, .size = @sizeOf(c.ke_world_transform_component), .alignment = @alignOf(c.ke_world_transform_component), .fields = null, .field_count = 0 }, out_error);
    ids.camera = registerComponent(e, c.KE_COMPONENT_NAME_CAMERA, c.ke_camera_component, &c.ke_camera_component_fields, out_error);
    ids.directional_light = registerComponent(e, c.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, c.ke_directional_light_component, &c.ke_directional_light_component_fields, out_error);
    ids.point_light = registerComponent(e, c.KE_COMPONENT_NAME_POINT_LIGHT, c.ke_point_light_component, &c.ke_point_light_component_fields, out_error);
    ids.spot_light = registerComponent(e, c.KE_COMPONENT_NAME_SPOT_LIGHT, c.ke_spot_light_component, &c.ke_spot_light_component_fields, out_error);
    ids.ambient_light = registerComponent(e, c.KE_COMPONENT_NAME_AMBIENT_LIGHT, c.ke_ambient_light_component, &c.ke_ambient_light_component_fields, out_error);
    ids.skybox = e.component_register.?(e, &c.ke_component_params{ .name = c.KE_COMPONENT_NAME_SKYBOX, .size = @sizeOf(c.ke_skybox_component), .alignment = @alignOf(c.ke_skybox_component), .fields = null, .field_count = 0 }, out_error);
    ids.sprite2d = registerComponent(e, c.KE_COMPONENT_NAME_SPRITE2D, c.ke_sprite2d_component, &c.ke_sprite2d_component_fields, out_error);
    ids.label = registerComponent(e, c.KE_COMPONENT_NAME_LABEL, c.ke_label_component, &c.ke_label_component_fields, out_error);
    inline for (@typeInfo(c.ke_render_scene_component_ids).@"struct".fields) |f| {
        if (@field(ids, f.name) == c.KE_COMPONENT_INVALID) return false;
    }
    return true;
}

fn refusedScene(out_error: [*c][*c]c.ke_error) c.ke_render_scene_resolve_handle {
    c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "scene resolve: runtime, ecs and service are required", @src().file, @intCast(@src().line), null);
    return .{ .ref = null, .destroy = null };
}

/// The factory declared in scene_resolve_create.h. A failed allocation fails as out of memory and
/// a component the ecs refuses with the ecs's error. The runtime refusing either system sets the
/// error output, removes the sprite system when it was the mesh system that was refused, and
/// returns the null handle.
export fn ke_render_scene_resolve_create(params_in: ?*const c.ke_render_scene_resolve_params, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_scene_resolve_handle {
    const empty = c.ke_render_scene_resolve_handle{ .ref = null, .destroy = null };
    const p = params_in orelse return refusedScene(out_error);
    const rt: *c.ke_runtime = p.runtime orelse return refusedScene(out_error);
    const e: *c.ke_ecs = p.ecs orelse return refusedScene(out_error);
    const core = p.service orelse return refusedScene(out_error);

    const st = gpa.create(SceneResolve) catch {
        c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "scene resolve: allocation failed", @src().file, @intCast(@src().line), null);
        return empty;
    };
    st.api = .{ .handle = st, .component_ids = componentIds };
    if (!registerIds(e, &st.ids, out_error)) {
        gpa.destroy(st);
        return empty;
    }

    st.sprite = .{ .core = core, .mesh_cid = st.ids.mesh, .resolver = p.resolver };
    st.sprite_terms = .{ .{ .cid = st.ids.sprite2d, .access = c.KE_ACCESS_WRITE }, .{ .cid = st.ids.mesh, .access = c.KE_ACCESS_WRITE }, .{ .cid = st.ids.sprite2d, .access = c.KE_ACCESS_WRITE } };
    st.sprite_queries = .{ .{ .terms = &st.sprite_terms[0], .term_count = 2 }, .{ .terms = &st.sprite_terms[2], .term_count = 1 } };
    var sprite = std.mem.zeroes(c.ke_runtime_system_params);
    sprite.name = "render.sprite2d.resolve";
    sprite.phase = c.KE_PHASE_UPDATE;
    sprite.queries = &st.sprite_queries;
    sprite.query_count = st.sprite_queries.len;
    sprite.pinned_thread = 0;
    sprite.user_data = &st.sprite;
    sprite.execute = sprite_resolve.system;
    const sprite_id = rt.register_system.?(rt, &sprite, out_error);
    if (sprite_id == 0) {
        gpa.destroy(st);
        return empty;
    }

    st.mesh_terms = .{.{ .cid = st.ids.mesh, .access = c.KE_ACCESS_WRITE }};
    st.mesh_queries = .{.{ .terms = &st.mesh_terms[0], .term_count = 1 }};
    var mesh = std.mem.zeroes(c.ke_runtime_system_params);
    mesh.name = "render.mesh.resolve";
    mesh.phase = c.KE_PHASE_UPDATE;
    mesh.queries = &st.mesh_queries;
    mesh.query_count = st.mesh_queries.len;
    mesh.pinned_thread = 0;
    mesh.user_data = core;
    mesh.execute = mesh_resolve.system;
    mesh.after = &mesh_resolve_after;
    mesh.after_count = mesh_resolve_after.len;
    if (rt.register_system.?(rt, &mesh, out_error) == 0) {
        _ = rt.unregister_system.?(rt, sprite_id, null);
        gpa.destroy(st);
        return empty;
    }

    return .{ .ref = &st.api, .destroy = destroyScene };
}

/// The state of one label resolve. The factory allocates it and `destroyLabel` frees it. The
/// runtime receives `state` as the context of the system, and its query points into it, so it is
/// not moved after creation.
const LabelResolve = struct {
    state: label_resolve.State,
    terms: [1]c.ke_component_access,
    queries: [1]c.ke_query_decl,
};

const label_resolve_before = [_][*c]const u8{"render.ui.labels"};

/// The `destroy` slot of the handle `ke_render_label_resolve_create` returns; a null argument is
/// ignored.
fn destroyLabel(self: ?*c.ke_render_label_resolve) callconv(.c) void {
    const st: *LabelResolve = @ptrCast(@alignCast(self orelse return));
    gpa.destroy(st);
}

/// The factory declared in label_resolve_create.h. A failed allocation fails as out of memory, and
/// the runtime refusing the system with the runtime's error.
export fn ke_render_label_resolve_create(params_in: ?*const c.ke_render_label_resolve_params, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_label_resolve_handle {
    const empty = c.ke_render_label_resolve_handle{ .ref = null, .destroy = null };
    const p = params_in orelse return refusedLabel(out_error);
    const rt: *c.ke_runtime = p.runtime orelse return refusedLabel(out_error);
    const core = p.service orelse return refusedLabel(out_error);
    const ui = p.ui orelse return refusedLabel(out_error);

    const st = gpa.create(LabelResolve) catch {
        c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "label resolve: allocation failed", @src().file, @intCast(@src().line), null);
        return empty;
    };
    st.state = .{ .core = core, .ui = ui, .resolver = p.resolver, .logger = p.logger };
    st.terms = .{.{ .cid = p.label_cid, .access = c.KE_ACCESS_WRITE }};
    st.queries = .{.{ .terms = &st.terms[0], .term_count = 1 }};
    var label = std.mem.zeroes(c.ke_runtime_system_params);
    label.name = "render.label.resolve";
    label.phase = c.KE_PHASE_UPDATE;
    label.queries = &st.queries;
    label.query_count = st.queries.len;
    label.pinned_thread = 0;
    label.user_data = &st.state;
    label.execute = label_resolve.system;
    label.before = &label_resolve_before;
    label.before_count = label_resolve_before.len;
    if (rt.register_system.?(rt, &label, out_error) == 0) {
        gpa.destroy(st);
        return empty;
    }
    return .{ .ref = @ptrCast(st), .destroy = destroyLabel };
}

fn refusedLabel(out_error: [*c][*c]c.ke_error) c.ke_render_label_resolve_handle {
    c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "label resolve: runtime, service and ui are required", @src().file, @intCast(@src().line), null);
    return .{ .ref = null, .destroy = null };
}

const testing = std.testing;

const Stubs = @import("stubs").Stubs(c);

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

    fn sceneParams(self: *Rig) c.ke_render_scene_resolve_params {
        return .{ .runtime = self.rt.api(), .ecs = self.ecs.api(), .service = self.core.api(), .resolver = null };
    }
};

test "the scene resolve registers both its systems and hands out an id for every component" {
    var rig: Rig = undefined;
    rig.init();
    const h = ke_render_scene_resolve_create(&rig.sceneParams(), null);
    try testing.expect(h.ref != null);
    try testing.expectEqual(@as(u32, 2), rig.rt.live_count);
    const ids = h.ref.*.component_ids.?(h.ref);
    inline for (@typeInfo(c.ke_render_scene_component_ids).@"struct".fields) |f| {
        try testing.expect(@field(ids.*, f.name) != c.KE_COMPONENT_INVALID);
    }
    h.destroy.?(h.ref);
}

test "a scene resolve whose mesh system the runtime refuses removes its sprite system and fails" {
    var rig: Rig = undefined;
    rig.init();
    rig.rt.limit = 1;
    try testing.expect(ke_render_scene_resolve_create(&rig.sceneParams(), null).ref == null);
    try testing.expectEqual(@as(u32, 0), rig.rt.live_count);
}

test "a scene resolve missing its service is refused as an invalid argument" {
    var rig: Rig = undefined;
    rig.init();
    var p = rig.sceneParams();
    p.service = null;
    var err: [*c]c.ke_error = null;
    try testing.expect(ke_render_scene_resolve_create(&p, &err).ref == null);
    try testing.expectEqual(&c.KE_ERROR_INVALID_ARGUMENT, err.*.type);
}

test "the label resolve registers its system, and fails when the runtime refuses it" {
    var rig: Rig = undefined;
    rig.init();
    var ui = std.mem.zeroes(c.ke_render_ui);
    const p = c.ke_render_label_resolve_params{ .runtime = rig.rt.api(), .service = rig.core.api(), .ui = &ui, .resolver = null, .logger = null, .label_cid = 7 };
    const h = ke_render_label_resolve_create(&p, null);
    try testing.expect(h.ref != null);
    try testing.expectEqual(@as(u32, 1), rig.rt.live_count);
    h.destroy.?(h.ref);

    rig.rt.limit = rig.rt.registered;
    try testing.expect(ke_render_label_resolve_create(&p, null).ref == null);
}

test "a label resolve missing its ui is refused as an invalid argument" {
    var rig: Rig = undefined;
    rig.init();
    const p = c.ke_render_label_resolve_params{ .runtime = rig.rt.api(), .service = rig.core.api(), .ui = null, .resolver = null, .logger = null, .label_cid = 7 };
    var err: [*c]c.ke_error = null;
    try testing.expect(ke_render_label_resolve_create(&p, &err).ref == null);
    try testing.expectEqual(&c.KE_ERROR_INVALID_ARGUMENT, err.*.type);
}

test "creating and destroying the scene resolve and the label resolve leaves no block allocated" {
    try heap.expectNoLeaks();
}
