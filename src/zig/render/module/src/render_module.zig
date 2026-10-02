const std = @import("std");
const cimport = @import("cimport.zig");
const component_apply = @import("component_apply.zig");
const mesh_resolve = @import("mesh_resolve.zig");
const sprite_resolve = @import("sprite_resolve.zig");
const label_resolve = @import("label_resolve.zig");

pub const c = cimport.c;

const heap = @import("heap");
pub const _DllMainCRTStartup = @import("heap")._DllMainCRTStartup;
const gpa = heap.gpa;

const ExecFn = ?*const fn (?*c.ke_system_ctx, ?*anyopaque, f32, [*c][*c]c.ke_error) callconv(.c) bool;

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
    mesh_resolve_queries_terms: [1]c.ke_component_access,
    mesh_resolve_queries: [1]c.ke_query_decl,
    sprite_resolve_queries_terms: [3]c.ke_component_access,
    sprite_resolve_queries: [2]c.ke_query_decl,
    sprite_resolve_state: sprite_resolve.State,
    label_resolve_queries_terms: [1]c.ke_component_access,
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
    camera: c.ke_render_camera_handle,
};

inline fn stateOf(user: ?*anyopaque) *ModuleState {
    return @alignCast(@ptrCast(user.?));
}

fn registerComponent(
    e: *c.ke_ecs,
    name: [*c]const u8,
    comptime T: type,
    comptime table: anytype,
) c.ke_component_id {
    const fields = @typeInfo(@TypeOf(table.*)).array;
    return e.component_register.?(e, name, @sizeOf(T), table, @intCast(fields.len), null);
}

fn beginFrameSys(_: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const st = stateOf(user);
    return st.core.ref.*.begin_frame.?(st.core.ref, out_error) != 0;
}

fn clearSys(_: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const st = stateOf(user);
    const pc = st.core.ref.*.begin_pass.?(st.core.ref, &st.io);
    if (pc == null) return true;
    const rp = pc.*.begin_render.?(pc);
    rp.*.end.?(rp);
    st.core.ref.*.end_pass.?(st.core.ref, pc);
    return true;
}

fn endFrameSys(_: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const st = stateOf(user);
    return st.core.ref.*.end_frame.?(st.core.ref, out_error) != 0;
}

fn registerSys(rt: *c.ke_runtime, name: [*c]const u8,
               access: [*c]const c.ke_component_access, access_count: u32,
               user: anytype, exec: ExecFn, out_error: [*c][*c]c.ke_error) bool {
    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = name;
    params.phase = c.KE_PHASE_RENDER;
    params.access_list = access;
    params.access_count = access_count;
    params.pinned_thread = 0;
    params.user_data = user;
    params.execute = exec;
    return rt.register_system.?(rt, &params, out_error) != 0;
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
    if (st.camera.destroy) |d| d(st.camera.ref);
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
    const sprite_cid = registerComponent(e, c.KE_COMPONENT_NAME_SPRITE2D, c.ke_sprite2d_component, &c.ke_sprite2d_component_fields);

    registerFields(w, mesh_cid, &c.ke_mesh_component_fields);
    registerFields(w, camera_cid, &c.ke_camera_component_fields);
    registerFields(w, light_cid, &c.ke_directional_light_component_fields);
    registerFields(w, point_light_cid, &c.ke_point_light_component_fields);
    registerFields(w, spot_light_cid, &c.ke_spot_light_component_fields);
    registerFields(w, ambient_light_cid, &c.ke_ambient_light_component_fields);
    registerFields(w, sprite_cid, &c.ke_sprite2d_component_fields);

    const label_cid = registerComponent(e, c.KE_COMPONENT_NAME_LABEL, c.ke_label_component, &c.ke_label_component_fields);
    registerFields(w, label_cid, &c.ke_label_component_fields);

    if (!w.register_component_apply.?(w, camera_cid, component_apply.ke_render_apply_camera, null, null)) return false;
    if (!w.register_component_apply.?(w, mesh_cid, component_apply.ke_render_apply_mesh, null, null)) return false;
    if (!w.register_component_apply.?(w, sprite_cid, component_apply.ke_render_apply_sprite2d, null, null)) return false;
    return true;
}

fn registerFields(w: *c.ke_world, cid: c.ke_component_id, table: anytype) void {
    const fields = @typeInfo(@TypeOf(table.*)).array;
    _ = w.register_component_fields.?(w, cid, table, @intCast(fields.len), null);
}

fn failCreate(rt: *c.ke_runtime, mark: c.ke_system_id, st: *ModuleState) c.ke_render_module_handle {
    while (rt.last_system.?(rt) > mark) {
        if (!rt.unregister_system.?(rt, rt.last_system.?(rt), null)) break;
    }
    destroyModule(@ptrCast(st));
    return empty;
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
    const mark = rt.last_system.?(rt);

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
    st.camera = .{ .ref = null, .destroy = null };
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
            return failCreate(rt, mark, st);
        };
        if (ndc.clip_left_handed == 0) {
            c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "render: no projection builds a right-handed clip space", @src().file, @intCast(@src().line), null);
            return failCreate(rt, mark, st);
        }

        st.camera = c.ke_render_camera_create(vs, &ndc, out_error);
        if (st.camera.ref == null) {
            return failCreate(rt, mark, st);
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

        st.mesh_resolve_queries_terms = .{ .{ .cid = mesh_cid, .access = c.KE_ACCESS_WRITE } };
        st.mesh_resolve_queries = .{ .{ .terms = &st.mesh_resolve_queries_terms[0], .term_count = 1 } };
        var mesh_resolve_params = std.mem.zeroes(c.ke_runtime_system_params);
        mesh_resolve_params.name = "render.mesh.resolve";
        mesh_resolve_params.phase = c.KE_PHASE_UPDATE;
        mesh_resolve_params.queries = &st.mesh_resolve_queries;
        mesh_resolve_params.query_count = st.mesh_resolve_queries.len;
        mesh_resolve_params.pinned_thread = 0;
        mesh_resolve_params.user_data = st.core.ref;
        mesh_resolve_params.execute = mesh_resolve.system;
        if (rt.register_system.?(rt, &mesh_resolve_params, out_error) == 0) {
            return failCreate(rt, mark, st);
        }

        const sprite_cid = registerComponent(e, c.KE_COMPONENT_NAME_SPRITE2D, c.ke_sprite2d_component, &c.ke_sprite2d_component_fields);
        st.sprite_resolve_state = .{ .core = st.core.ref, .mesh_cid = mesh_cid, .resolver = asset_resolver };
        st.sprite_resolve_queries_terms = .{ .{ .cid = sprite_cid, .access = c.KE_ACCESS_WRITE }, .{ .cid = mesh_cid, .access = c.KE_ACCESS_WRITE }, .{ .cid = sprite_cid, .access = c.KE_ACCESS_WRITE } };
        st.sprite_resolve_queries = .{ .{ .terms = &st.sprite_resolve_queries_terms[0], .term_count = 2 }, .{ .terms = &st.sprite_resolve_queries_terms[2], .term_count = 1 } };
        var sprite_resolve_params = std.mem.zeroes(c.ke_runtime_system_params);
        sprite_resolve_params.name = "render.sprite2d.resolve";
        sprite_resolve_params.phase = c.KE_PHASE_UPDATE;
        sprite_resolve_params.queries = &st.sprite_resolve_queries;
        sprite_resolve_params.query_count = st.sprite_resolve_queries.len;
        sprite_resolve_params.pinned_thread = 0;
        sprite_resolve_params.user_data = &st.sprite_resolve_state;
        sprite_resolve_params.execute = sprite_resolve.system;
        if (rt.register_system.?(rt, &sprite_resolve_params, out_error) == 0) {
            return failCreate(rt, mark, st);
        }

        if (!registerSys(rt, "render.begin_frame", &st.begin_access, st.begin_access.len, st, beginFrameSys, out_error)) {
            return failCreate(rt, mark, st);
        }
        if (!registerSys(rt, "render.clear", &st.clear_access, st.clear_access.len, st, clearSys, out_error)) {
            return failCreate(rt, mark, st);
        }

        st.shadow = c.ke_render_shadow_create(rt, st.core.ref, dev, ndc, vs, @intFromBool(shadow_enabled),
                                              mesh_cid, world_transform_cid, light_cid, st.frame_cid, shadow_params, out_error);
        if (st.shadow.ref == null) {
            return failCreate(rt, mark, st);
        }

        st.cluster = c.ke_render_cluster_create(rt, st.core.ref, dev, logger, grid_x, grid_y, grid_z, max_lights_per_cluster,
                                                point_light_cid, spot_light_cid, world_transform_cid, camera_cid, st.frame_cid, vs, st.camera.ref, out_error);
        if (st.cluster.ref == null) {
            return failCreate(rt, mark, st);
        }

        st.gbuffer = c.ke_render_gbuffer_create(rt, st.core.ref, dev, st.camera.ref, mesh_cid, world_transform_cid, camera_cid, st.frame_cid, out_error);
        if (st.gbuffer.ref == null) {
            return failCreate(rt, mark, st);
        }

        st.deferred = c.ke_render_deferred_lighting_create(rt, st.core.ref, dev, st.camera.ref, logger, @intFromBool(ibl_enabled),
                                                            camera_cid, world_transform_cid, light_cid, ambient_cid, skybox_cid, st.frame_cid, out_error);
        if (st.deferred.ref == null) {
            return failCreate(rt, mark, st);
        }
        st.skybox = c.ke_render_skybox_create(rt, st.core.ref, dev, st.camera.ref, camera_cid, world_transform_cid, skybox_cid, st.frame_cid, out_error);
        if (st.skybox.ref == null) {
            return failCreate(rt, mark, st);
        }
        st.forward = c.ke_render_forward_create(rt, st.core.ref, dev, st.camera.ref, logger, @intFromBool(ibl_enabled),
                                                mesh_cid, world_transform_cid, camera_cid, light_cid, ambient_cid, skybox_cid, st.frame_cid, out_error);
        if (st.forward.ref == null) {
            return failCreate(rt, mark, st);
        }
        st.tonemap = c.ke_render_tonemap_create(rt, st.core.ref, dev, logger, out_error);
        if (st.tonemap.ref == null) {
            return failCreate(rt, mark, st);
        }
        st.ui = c.ke_render_ui_create(rt, e, st.core.ref, dev, ndc, bb_cid, 8, out_error);
        if (st.ui.ref == null) {
            return failCreate(rt, mark, st);
        }

        const label_cid = registerComponent(e, c.KE_COMPONENT_NAME_LABEL, c.ke_label_component, &c.ke_label_component_fields);
        st.label_resolve_state = .{ .core = st.core.ref, .ui = st.ui.ref, .resolver = asset_resolver, .logger = logger };
        st.label_resolve_queries_terms = .{ .{ .cid = label_cid, .access = c.KE_ACCESS_WRITE } };
        st.label_resolve_queries = .{ .{ .terms = &st.label_resolve_queries_terms[0], .term_count = 1 } };
        var label_resolve_params = std.mem.zeroes(c.ke_runtime_system_params);
        label_resolve_params.name = "render.label.resolve";
        label_resolve_params.phase = c.KE_PHASE_UPDATE;
        label_resolve_params.queries = &st.label_resolve_queries;
        label_resolve_params.query_count = st.label_resolve_queries.len;
        label_resolve_params.pinned_thread = 0;
        label_resolve_params.user_data = &st.label_resolve_state;
        label_resolve_params.execute = label_resolve.system;
        if (rt.register_system.?(rt, &label_resolve_params, out_error) == 0) {
            return failCreate(rt, mark, st);
        }

        if (!registerSys(rt, "render.end_frame", &st.end_access, st.end_access.len, st, endFrameSys, out_error)) {
            return failCreate(rt, mark, st);
        }
    }

    return .{ .ref = @ptrCast(st), .destroy = destroyModule };
}

const testing = std.testing;

const Stubs = @import("stubs").Stubs(c);

const authored_shaders = [_][]const u8{
    "cluster_cull.cs.wgsl",
    "standard.gbuffer.vs.wgsl",
    "standard.gbuffer.fs.wgsl",
    "standard.forward.vs.wgsl",
    "standard.forward.fs.wgsl",
    "deferred_lighting.vs.wgsl",
    "deferred_lighting.fs.wgsl",
    "shadow.vs.wgsl",
    "shadow.fs.wgsl",
    "skybox.vs.wgsl",
    "skybox.fs.wgsl",
    "tonemap.vs.wgsl",
    "tonemap.fs.wgsl",
    "ui.vs.wgsl",
    "ui.fs.wgsl",
};

const Rig = struct {
    dev: Stubs.Device,
    ecs: Stubs.Ecs,
    rt: Stubs.Runtime,
    world: Stubs.World,
    shaders: std.testing.TmpDir,
    shader_dir: [std.fs.max_path_bytes]u8,

    fn init(self: *Rig) !void {
        self.dev.init();
        self.ecs.init();
        self.rt.init();
        self.world.init();
        self.shaders = std.testing.tmpDir(.{});
        errdefer self.shaders.cleanup();
        for (authored_shaders) |name| {
            try self.shaders.dir.writeFile(testing.io, .{ .sub_path = name, .data = "// stand-in" });
        }
        const dir = try std.fmt.bufPrint(&self.shader_dir, ".zig-cache/tmp/{s}", .{self.shaders.sub_path});
        self.shader_dir[dir.len] = 0;
    }

    fn deinit(self: *Rig) void {
        self.shaders.cleanup();
    }

    fn create(self: *Rig) c.ke_render_module_handle {
        const dir: [*:0]const u8 = @ptrCast(&self.shader_dir);
        return ke_render_module_create(self.rt.api(), self.ecs.api(), self.dev.api(), self.world.api(), 1, null, null, null, null, null, null, dir, null);
    }
};

test "creating and destroying the render module with its default passes leaves no block allocated and no GPU resource live" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = rig.create();
    try testing.expect(h.ref != null);
    try testing.expect(rig.rt.registered > 0);
    h.destroy.?(h.ref);
    try testing.expectEqual(@as(i64, 0), rig.dev.live);
    try heap.expectNoLeaks();
}

test "a render module that fails at any GPU resource it creates gives back everything it had created before" {
    var full: Rig = undefined;
    try full.init();
    defer full.deinit();
    const whole = full.create();
    try testing.expect(whole.ref != null);
    whole.destroy.?(whole.ref);
    const fallible_total = full.dev.fallible_created;
    try testing.expect(fallible_total > 0);

    var budget: u32 = 0;
    while (budget < fallible_total) : (budget += 1) {
        var rig: Rig = undefined;
        try rig.init();
        defer rig.deinit();
        rig.dev.fallible_budget = budget;
        const h = rig.create();
        if (h.ref != null) h.destroy.?(h.ref);
        try testing.expectEqual(@as(i64, 0), rig.dev.live);
        try heap.expectNoLeaks();
    }
}

test "a render module whose runtime refuses any one system registration fails the create and gives back what it had created" {
    var full: Rig = undefined;
    try full.init();
    const h = full.create();
    try testing.expect(h.ref != null);
    const system_total = full.rt.registered;
    h.destroy.?(h.ref);
    full.deinit();
    try testing.expect(system_total > 0);

    var limit: u32 = 0;
    while (limit < system_total) : (limit += 1) {
        var rig: Rig = undefined;
        try rig.init();
        defer rig.deinit();
        rig.rt.limit = limit;
        const failed = rig.create();
        try testing.expect(failed.ref == null);
        try testing.expectEqual(@as(u32, 0), rig.rt.live_count);
        try testing.expectEqual(@as(i64, 0), rig.dev.live);
        try heap.expectNoLeaks();
    }
}

fn failingFrame(_: [*c]c.ke_render_service, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_bool {
    c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "no backbuffer", @src().file, @intCast(@src().line), null);
    return 0;
}

test "a frame the service cannot begin or end fails the render phase with the service's own error" {
    var svc = std.mem.zeroes(c.ke_render_service);
    svc.begin_frame = failingFrame;
    svc.end_frame = failingFrame;
    var st: ModuleState = undefined;
    st.core = .{ .ref = &svc, .destroy = null };

    var err: [*c]c.ke_error = null;
    try testing.expect(!beginFrameSys(null, &st, 0.0, &err));
    try testing.expect(err != null);
    try testing.expectEqualStrings("no backbuffer", std.mem.span(err.*.message));

    err = null;
    try testing.expect(!endFrameSys(null, &st, 0.0, &err));
    try testing.expect(err != null);
}

test "a render module without a runtime, an ecs or a device is refused" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try testing.expect(ke_render_module_create(null, rig.ecs.api(), rig.dev.api(), null, 1, null, null, null, null, null, null, "shaders", null).ref == null);
    try testing.expect(ke_render_module_create(rig.rt.api(), null, rig.dev.api(), null, 1, null, null, null, null, null, null, "shaders", null).ref == null);
    try testing.expect(ke_render_module_create(rig.rt.api(), rig.ecs.api(), null, null, 1, null, null, null, null, null, null, "shaders", null).ref == null);
    try heap.expectNoLeaks();
}
