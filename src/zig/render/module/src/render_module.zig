const std = @import("std");
const cimport = @import("cimport.zig");
const component_apply = @import("component_apply.zig");
const mesh_resolve = @import("mesh_resolve.zig");
const sprite_resolve = @import("sprite_resolve.zig");
const label_resolve = @import("label_resolve.zig");

pub const c = cimport.c;

const gpa = std.heap.c_allocator;

const ExecFn = ?*const fn (?*c.ke_system_ctx, ?*anyopaque, f32) callconv(.c) void;

const DEFAULT_GRID_X: u32 = 32;
const DEFAULT_GRID_Y: u32 = 18;
const DEFAULT_GRID_Z: u32 = 24;
const DEFAULT_MAX_LIGHTS_PER_CLUSTER: u32 = 256;

const ModuleState = struct {
    core: c.ke_render_service_handle,
    device: *c.ke_gpu_device,
    ndc: c.ke_ndc_convention,
    logger: ?*c.ke_logger,

    bb_writes: [1][*c]const u8,
    io: c.ke_render_pass_io,
    frame_cid: c.ke_component_id,
    begin_access: [2]c.ke_component_access,
    clear_access: [2]c.ke_component_access,
    end_access: [2]c.ke_component_access,
    mesh_resolve_queries: [1]c.ke_query_decl,
    sprite_resolve_queries: [2]c.ke_query_decl,
    sprite_resolve_state: sprite_resolve.State,
    label_resolve_queries: [1]c.ke_query_decl,
    label_resolve_state: label_resolve.State,

    shadow: c.ke_render_shadow_handle,
    cluster: c.ke_render_cluster_handle,
    gbuffer: c.ke_render_gbuffer_handle,
    deferred: c.ke_render_deferred_lighting_handle,
    skybox: c.ke_render_skybox_handle,
    forward: c.ke_render_forward_handle,
    tonemap: c.ke_render_tonemap_handle,
    ui: c.ke_render_ui_handle,

    view_space: c.ke_view_space_handle,
    owns_view_space: bool,
};

inline fn stateOf(user: ?*anyopaque) *ModuleState {
    return @alignCast(@ptrCast(user.?));
}

/// Registers a component with the generated table describing its layout, taking
/// the field count from the table.
fn registerComponent(
    e: *c.ke_ecs,
    name: [*c]const u8,
    comptime T: type,
    comptime table: anytype,
) c.ke_component_id {
    const fields = @typeInfo(@TypeOf(table.*)).array;
    return e.component_register.?(e, name, @sizeOf(T), table, @intCast(fields.len), null);
}

fn beginFrameSys(_: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    _ = st.core.ref.*.begin_frame.?(st.core.ref, null);
}

fn clearSys(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    const pc = st.core.ref.*.begin_pass.?(st.core.ref, ctx, &st.io);
    if (pc == null) return;
    const rp = pc.*.begin_render.?(pc);
    rp.*.end.?(rp);
    st.core.ref.*.end_pass.?(st.core.ref, pc);
}

fn endFrameSys(_: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    _ = st.core.ref.*.end_frame.?(st.core.ref, null);
}

fn registerSys(rt: *c.ke_runtime, name: [*c]const u8,
               queries: [*c]const c.ke_query_decl, query_count: u32,
               access: [*c]const c.ke_component_access, access_count: u32,
               user: anytype, exec: ExecFn) void {
    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = name;
    params.phase = c.KE_PHASE_RENDER;
    params.queries = queries;
    params.query_count = query_count;
    params.access_list = access;
    params.access_count = access_count;
    params.pinned_thread = 0;
    params.user_data = user;
    params.execute = exec;
    _ = rt.register_system.?(rt, &params, null);
}

export fn ke_render_module_core(module: ?*c.ke_render_module) callconv(.c) ?*c.ke_render_service {
    const st: *ModuleState = @alignCast(@ptrCast(module orelse return null));
    return st.core.ref;
}

export fn ke_render_module_load_font(module: ?*c.ke_render_module, key: [*c]const u8,
                                     atlas: c.ke_texture_handle, glyphs: [*c]const c.ke_glyph_metrics,
                                     glyph_count: u32, line_height: f32, ascent: f32,
                                     out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_ui_font_handle {
    const st: *ModuleState = @alignCast(@ptrCast(module orelse return c.KE_UI_FONT_NONE));
    return st.ui.ref.*.load_font.?(st.ui.ref, key, atlas, glyphs, glyph_count, line_height, ascent, out_error);
}

fn destroyModule(self: ?*c.ke_render_module) callconv(.c) void {
    const st: *ModuleState = @alignCast(@ptrCast(self orelse return));
    if (st.tonemap.destroy) |d| d(st.tonemap.ref);
    if (st.skybox.destroy) |d| d(st.skybox.ref);
    if (st.ui.destroy) |d| d(st.ui.ref);
    if (st.forward.destroy) |d| d(st.forward.ref);
    if (st.deferred.destroy) |d| d(st.deferred.ref);
    if (st.gbuffer.destroy) |d| d(st.gbuffer.ref);
    if (st.shadow.destroy) |d| d(st.shadow.ref);
    if (st.cluster.destroy) |d| d(st.cluster.ref);
    if (st.core.destroy) |d| d(st.core.ref);
    if (st.owns_view_space) {
        if (st.view_space.destroy) |d| d(st.view_space.ref);
    }
    gpa.destroy(st);
}

const empty = c.ke_render_module_handle{ .ref = null, .destroy = null };

export fn ke_render_register_scene_apply(ecs: ?*c.ke_ecs, world: ?*c.ke_world) callconv(.c) bool {
    const e = ecs orelse return false;
    const w = world orelse return false;

    const mesh_cid = registerComponent(e, c.KE_COMPONENT_NAME_MESH, c.ke_mesh_component, &c.ke_mesh_component_fields);
    const camera_cid = registerComponent(e, c.KE_COMPONENT_NAME_CAMERA, c.ke_camera_component, &c.ke_camera_component_fields);
    const light_cid = registerComponent(e, c.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, c.ke_directional_light_component, &c.ke_directional_light_component_fields);
    const point_light_cid = registerComponent(e, c.KE_COMPONENT_NAME_POINT_LIGHT, c.ke_point_light_component, &c.ke_point_light_component_fields);
    const spot_light_cid = registerComponent(e, c.KE_COMPONENT_NAME_SPOT_LIGHT, c.ke_spot_light_component, &c.ke_spot_light_component_fields);
    const ambient_light_cid = registerComponent(e, c.KE_COMPONENT_NAME_AMBIENT_LIGHT, c.ke_ambient_light_component, &c.ke_ambient_light_component_fields);
    _ = e.component_register.?(e, c.KE_COMPONENT_NAME_SKYBOX, @sizeOf(c.ke_skybox_component), null, 0, null);
    const sprite_cid = registerComponent(e, c.KE_COMPONENT_NAME_SPRITE_2D, c.ke_sprite2d_component, &c.ke_sprite2d_component_fields);

    registerFields(w, mesh_cid, &c.ke_mesh_component_fields);
    registerFields(w, camera_cid, &c.ke_camera_component_fields);
    registerFields(w, light_cid, &c.ke_directional_light_component_fields);
    registerFields(w, point_light_cid, &c.ke_point_light_component_fields);
    registerFields(w, spot_light_cid, &c.ke_spot_light_component_fields);
    registerFields(w, ambient_light_cid, &c.ke_ambient_light_component_fields);
    registerFields(w, sprite_cid, &c.ke_sprite2d_component_fields);

    const label_cid = registerComponent(e, c.KE_COMPONENT_NAME_LABEL, c.ke_label_component, &c.ke_label_component_fields);
    registerFields(w, label_cid, &c.ke_label_component_fields);

    _ = w.register_component_apply.?(w, camera_cid, component_apply.ke_render_apply_camera, null);
    _ = w.register_component_apply.?(w, mesh_cid, component_apply.ke_render_apply_mesh, null);
    _ = w.register_component_apply.?(w, sprite_cid, component_apply.ke_render_apply_sprite2d, null);
    return true;
}

/// Registers a generated field table, taking its length from the array type so
/// the count can never drift from the table it describes.
fn registerFields(w: *c.ke_world, cid: c.ke_component_id, table: anytype) void {
    const fields = @typeInfo(@TypeOf(table.*)).array;
    _ = w.register_component_fields.?(w, cid, table, @intCast(fields.len), null);
}

export fn ke_render_module_create(runtime: ?*c.ke_runtime, ecs: ?*c.ke_ecs, device: ?*c.ke_gpu_device,
                                  world: ?*c.ke_world, default_passes: c.ke_bool, logger: ?*c.ke_logger,
                                  asset_resolver: ?*c.ke_asset_resolver,
                                  cluster_params: ?*const c.ke_render_cluster_params,
                                  feature_params: ?*const c.ke_render_feature_params,
                                  shadow_params: ?*const c.ke_render_shadow_params,
                                  view_space: ?*c.ke_view_space,
                                  shader_dir: [*c]const u8, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_module_handle {
    const rt = runtime orelse return empty;
    const e = ecs orelse return empty;
    const dev = device orelse return empty;

    const core_h = c.ke_render_service_create(dev, e, shader_dir, out_error);
    if (core_h.ref == null) return empty;

    const st = gpa.create(ModuleState) catch {
        if (core_h.destroy) |d| d(core_h.ref);
        return empty;
    };
    st.core = core_h;
    st.device = dev;
    var grid_x: u32 = undefined;
    var grid_y: u32 = undefined;
    var grid_z: u32 = undefined;
    var max_lights_per_cluster: u32 = undefined;
    if (cluster_params) |p| {
        grid_x = if (p.grid_x != 0) p.grid_x else DEFAULT_GRID_X;
        grid_y = if (p.grid_y != 0) p.grid_y else DEFAULT_GRID_Y;
        grid_z = if (p.grid_z != 0) p.grid_z else DEFAULT_GRID_Z;
        max_lights_per_cluster = if (p.max_lights_per_cluster != 0) p.max_lights_per_cluster else DEFAULT_MAX_LIGHTS_PER_CLUSTER;
    } else {
        grid_x = DEFAULT_GRID_X;
        grid_y = DEFAULT_GRID_Y;
        grid_z = DEFAULT_GRID_Z;
        max_lights_per_cluster = DEFAULT_MAX_LIGHTS_PER_CLUSTER;
    }
    st.shadow = .{ .ref = null, .destroy = null };
    st.cluster = .{ .ref = null, .destroy = null };
    st.gbuffer = .{ .ref = null, .destroy = null };
    st.deferred = .{ .ref = null, .destroy = null };
    st.skybox = .{ .ref = null, .destroy = null };
    st.forward = .{ .ref = null, .destroy = null };
    st.tonemap = .{ .ref = null, .destroy = null };
    st.ui = .{ .ref = null, .destroy = null };
    st.view_space = .{ .ref = null, .destroy = null };
    st.owns_view_space = false;
    const shadow_enabled = if (feature_params) |p| p.enable_shadows != 0 else true;
    const ibl_enabled = if (feature_params) |p| p.enable_ibl != 0 else true;
    st.logger = logger;
    st.bb_writes = .{"backbuffer"};
    st.io = std.mem.zeroes(c.ke_render_pass_io);
    st.io.writes = @ptrCast(&st.bb_writes);
    st.io.writes_count = 1;
    st.io.cmd_slot = 0;

    const bb_cid = core_h.ref.*.cid.?(core_h.ref, "backbuffer");
    st.frame_cid = e.component_register.?(e, "render.frame", 0, null, 0, null);
    st.begin_access = .{
        .{ .cid = bb_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = st.frame_cid, .access = c.KE_ACCESS_WRITE },
    };
    st.clear_access = .{
        .{ .cid = bb_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = st.frame_cid, .access = c.KE_ACCESS_READ },
    };
    st.end_access = .{
        .{ .cid = bb_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.frame_cid, .access = c.KE_ACCESS_WRITE },
    };

    if (default_passes != 0) {
        const ndc = dev.get_ndc_convention.?(dev);
        if (view_space) |supplied| {
            st.view_space = .{ .ref = supplied, .destroy = null };
        } else {
            st.view_space = c.ke_view_space_rh_create(out_error);
            st.owns_view_space = true;
        }
        const vs = st.view_space.ref orelse {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        };
        if (ndc.clip_left_handed == 0) {
            c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "render: no projection builds a right-handed clip space", @src().file, @intCast(@src().line), null);
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }

        const mesh_cid = registerComponent(e, c.KE_COMPONENT_NAME_MESH, c.ke_mesh_component, &c.ke_mesh_component_fields);
        const world_transform_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_WORLD_TRANSFORM, @sizeOf(c.ke_world_transform_component), null, 0, null);
        const camera_cid = registerComponent(e, c.KE_COMPONENT_NAME_CAMERA, c.ke_camera_component, &c.ke_camera_component_fields);
        const light_cid = registerComponent(e, c.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, c.ke_directional_light_component, &c.ke_directional_light_component_fields);
        const point_light_cid = registerComponent(e, c.KE_COMPONENT_NAME_POINT_LIGHT, c.ke_point_light_component, &c.ke_point_light_component_fields);
        const spot_light_cid = registerComponent(e, c.KE_COMPONENT_NAME_SPOT_LIGHT, c.ke_spot_light_component, &c.ke_spot_light_component_fields);
        const ambient_cid = registerComponent(e, c.KE_COMPONENT_NAME_AMBIENT_LIGHT, c.ke_ambient_light_component, &c.ke_ambient_light_component_fields);
        const skybox_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_SKYBOX, @sizeOf(c.ke_skybox_component), null, 0, null);

        _ = ke_render_register_scene_apply(e, world);

        st.mesh_resolve_queries[0].terms[0] = .{ .cid = mesh_cid, .access = c.KE_ACCESS_WRITE };
        st.mesh_resolve_queries[0].term_count = 1;
        var mesh_resolve_params = std.mem.zeroes(c.ke_runtime_system_params);
        mesh_resolve_params.name = "render.mesh.resolve";
        mesh_resolve_params.phase = c.KE_PHASE_UPDATE;
        mesh_resolve_params.queries = &st.mesh_resolve_queries;
        mesh_resolve_params.query_count = st.mesh_resolve_queries.len;
        mesh_resolve_params.pinned_thread = 0;
        mesh_resolve_params.user_data = st.core.ref;
        mesh_resolve_params.execute = mesh_resolve.system;
        _ = rt.register_system.?(rt, &mesh_resolve_params, null);

        const sprite_cid = registerComponent(e, c.KE_COMPONENT_NAME_SPRITE_2D, c.ke_sprite2d_component, &c.ke_sprite2d_component_fields);
        st.sprite_resolve_state = .{ .core = st.core.ref, .mesh_cid = mesh_cid, .resolver = asset_resolver };
        st.sprite_resolve_queries = std.mem.zeroes([2]c.ke_query_decl);
        st.sprite_resolve_queries[0].terms[0] = .{ .cid = sprite_cid, .access = c.KE_ACCESS_WRITE };
        st.sprite_resolve_queries[0].terms[1] = .{ .cid = mesh_cid, .access = c.KE_ACCESS_WRITE };
        st.sprite_resolve_queries[0].term_count = 2;
        st.sprite_resolve_queries[1].terms[0] = .{ .cid = sprite_cid, .access = c.KE_ACCESS_WRITE };
        st.sprite_resolve_queries[1].term_count = 1;
        var sprite_resolve_params = std.mem.zeroes(c.ke_runtime_system_params);
        sprite_resolve_params.name = "render.sprite2d.resolve";
        sprite_resolve_params.phase = c.KE_PHASE_UPDATE;
        sprite_resolve_params.queries = &st.sprite_resolve_queries;
        sprite_resolve_params.query_count = st.sprite_resolve_queries.len;
        sprite_resolve_params.pinned_thread = 0;
        sprite_resolve_params.user_data = &st.sprite_resolve_state;
        sprite_resolve_params.execute = sprite_resolve.system;
        _ = rt.register_system.?(rt, &sprite_resolve_params, null);

        registerSys(rt, "render.begin_frame", null, 0, &st.begin_access, st.begin_access.len, st, beginFrameSys);
        registerSys(rt, "render.clear", null, 0, &st.clear_access, st.clear_access.len, st, clearSys);

        st.shadow = c.ke_render_shadow_create(rt, st.core.ref, dev, ndc, vs, @intFromBool(shadow_enabled),
                                              mesh_cid, world_transform_cid, light_cid, st.frame_cid, shadow_params, out_error);
        if (st.shadow.ref == null) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }

        st.cluster = c.ke_render_cluster_create(rt, st.core.ref, dev, logger, grid_x, grid_y, grid_z, max_lights_per_cluster,
                                                point_light_cid, spot_light_cid, world_transform_cid, camera_cid, st.frame_cid, vs, out_error);
        if (st.cluster.ref == null) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }

        st.gbuffer = c.ke_render_gbuffer_create(rt, st.core.ref, dev, ndc, vs, mesh_cid, world_transform_cid, camera_cid, st.frame_cid, out_error);
        if (st.gbuffer.ref == null) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }

        st.deferred = c.ke_render_deferred_lighting_create(rt, st.core.ref, dev, ndc, vs, logger, @intFromBool(ibl_enabled),
                                                            camera_cid, world_transform_cid, light_cid, ambient_cid, skybox_cid, st.frame_cid, out_error);
        if (st.deferred.ref == null) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }
        st.skybox = c.ke_render_skybox_create(rt, st.core.ref, dev, ndc, vs, camera_cid, world_transform_cid, skybox_cid, st.frame_cid, out_error);
        if (st.skybox.ref == null) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }
        st.forward = c.ke_render_forward_create(rt, st.core.ref, dev, ndc, vs, logger, @intFromBool(ibl_enabled),
                                                mesh_cid, world_transform_cid, camera_cid, light_cid, ambient_cid, skybox_cid, st.frame_cid, out_error);
        if (st.forward.ref == null) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }
        st.tonemap = c.ke_render_tonemap_create(rt, st.core.ref, dev, logger, out_error);
        if (st.tonemap.ref == null) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }
        st.ui = c.ke_render_ui_create(rt, e, st.core.ref, dev, ndc, bb_cid, 8, out_error);
        if (st.ui.ref == null) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }

        const label_cid = registerComponent(e, c.KE_COMPONENT_NAME_LABEL, c.ke_label_component, &c.ke_label_component_fields);
        st.label_resolve_state = .{ .core = st.core.ref, .ui = st.ui.ref, .resolver = asset_resolver };
        st.label_resolve_queries = std.mem.zeroes([1]c.ke_query_decl);
        st.label_resolve_queries[0].terms[0] = .{ .cid = label_cid, .access = c.KE_ACCESS_WRITE };
        st.label_resolve_queries[0].term_count = 1;
        var label_resolve_params = std.mem.zeroes(c.ke_runtime_system_params);
        label_resolve_params.name = "render.label.resolve";
        label_resolve_params.phase = c.KE_PHASE_UPDATE;
        label_resolve_params.queries = &st.label_resolve_queries;
        label_resolve_params.query_count = st.label_resolve_queries.len;
        label_resolve_params.pinned_thread = 0;
        label_resolve_params.user_data = &st.label_resolve_state;
        label_resolve_params.execute = label_resolve.system;
        _ = rt.register_system.?(rt, &label_resolve_params, null);

        registerSys(rt, "render.end_frame", null, 0, &st.end_access, st.end_access.len, st, endFrameSys);
    }

    return .{ .ref = @ptrCast(st), .destroy = destroyModule };
}
