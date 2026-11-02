//! The shadow pass: the render-phase system "render.shadow" that draws the meshes of the scene into
//! a depth map seen from the directional light, and publishes the light matrix. It also owns the
//! creation and teardown of that pass, behind the one factory it exports.

const abi_framework = @import("abi_framework");
const abi_render_contract = @import("abi_render_contract");
const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_components = @import("abi_render_components");
const abi_render_gpu = @import("abi_render_gpu");
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_shadow").logFn };

const zm = @import("zmath");
const abi_ecs = @import("abi_ecs");
const abi_math = @import("abi_math");
const abi_render = @import("abi_render");
const abi_render_shadow_factory = @import("abi_render_shadow_factory");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const abi_spatial = @import("abi_spatial");
const abi_view = @import("abi_view");
const R = @import("result").Result(.{});
const log = std.log.scoped(.render_shadow);

const heap = @import("heap");
const gpa = heap.gpa;

/// The shape of the shadow map: the params' fields of the same names, zero taking these values.
const Shape = struct {
    resolution: u32 = 1024,
    light_distance: f32 = 25.0,
    extent: f32 = 20.0,
    near_plane: f32 = 0.1,
    far_plane: f32 = 50.0,
};

fn shapeOf(p: *const abi_render_shadow_factory.c.ke_render_shadow_params) Shape {
    const d = Shape{};
    return .{
        .resolution = if (p.resolution != 0) p.resolution else d.resolution,
        .light_distance = if (p.light_distance != 0.0) p.light_distance else d.light_distance,
        .extent = if (p.extent != 0.0) p.extent else d.extent,
        .near_plane = if (p.near_plane != 0.0) p.near_plane else d.near_plane,
        .far_plane = if (p.far_plane != 0.0) p.far_plane else d.far_plane,
    };
}

const ShadowObj = extern struct { model: [16]f32 };

const Objects = @import("object_uniforms").ObjectUniforms(ShadowObj);

const object_hint = [_]abi_render_gpu.c.ke_render_binding_hint{.{ .name = "object", .flags = abi_render_gpu.c.KE_RENDER_BINDING_HINT_DYNAMIC_OFFSET }};

const shader_layout = abi_render_gpu.c.ke_render_shader_layout_params{
    .shader = "shadow",
    .stages = abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX | abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT,
    .hints = &object_hint,
    .hint_count = object_hint.len,
};

/// The state of one shadow pass, allocated by `ke_render_shadow_create` and freed by
/// `destroyHandle`. The registered system keeps a pointer to it as user data from registration on.
/// Fields that `setup` has not reached keep their initial values, so `destroyModule` releases only
/// what exists. `names` holds the module's copies of the map, depth and light names of its group.
/// `destroyHandle` unregisters the system the factory registered before it frees the module.
const ShadowModule = struct {
    runtime: *abi_runtime.c.ke_runtime = undefined,
    system: abi_framework.c.ke_system_id = 0,
    core: *abi_render.c.ke_render_service = undefined,
    device: *abi_render_gpu.c.ke_gpu_device = undefined,
    ndc: abi_render_gpu.c.ke_ndc_convention = undefined,
    view_space: *abi_view.c.ke_view_space = undefined,
    params: Shape = .{},
    names: [3]?[:0]u8 = .{ null, null, null },
    mesh_cid: abi_asset_resolver.c.ke_component_id = undefined,
    world_transform_cid: abi_asset_resolver.c.ke_component_id = undefined,
    light_cid: abi_asset_resolver.c.ke_component_id = undefined,
    frame_cid: abi_asset_resolver.c.ke_component_id = undefined,

    view: abi_asset_resolver.c.ke_gpu_texture_view = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    pipeline_params: abi_render_gpu.c.ke_gpu_render_pipeline_params = undefined,
    lvp_uniform: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    binder: *abi_render_gpu.c.ke_render_resource_binder = undefined,
    layout: abi_asset_resolver.c.ke_render_shader_layout = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    light_set: abi_asset_resolver.c.ke_render_resource_set = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    objects: ?Objects = null,

    writes: [2][*c]const u8 = undefined,
    io: abi_render.c.ke_render_pass_io = undefined,
    access: [6]abi_runtime.c.ke_component_access = undefined,
    queries_terms: [3]abi_runtime.c.ke_component_access = undefined,
    queries: [2]abi_runtime.c.ke_query_decl = undefined,
};

/// Called by `system` each tick with the direction it read from the directional light. The result
/// is the matrix uploaded to the light uniform, which is bound to group 0 for the pass.
fn lightViewProj(vs: *abi_view.c.ke_view_space, ndc: abi_render_gpu.c.ke_ndc_convention, p: Shape, ldir_in: zm.Vec) zm.Mat {
    const ldir = zm.normalize3(ldir_in);
    const eye3 = ldir * zm.f32x4s(-p.light_distance);
    const eye = abi_math.c.ke_vec3{ .x = eye3[0], .y = eye3[1], .z = eye3[2] };
    const origin = abi_math.c.ke_vec3{ .x = 0, .y = 0, .z = 0 };
    const up = if (@abs(ldir[1]) > 0.99)
        abi_math.c.ke_vec3{ .x = 0, .y = 0, .z = 1 }
    else
        abi_math.c.ke_vec3{ .x = 0, .y = 1, .z = 0 };

    var view: abi_math.c.ke_mat4 = undefined;
    vs.look_at.?(vs, &eye, &origin, &up, &view);
    var proj: abi_math.c.ke_mat4 = undefined;
    vs.orthographic.?(vs, p.extent, p.extent, p.near_plane, p.far_plane, &ndc, &proj);
    return zm.mul(zm.loadMat(&view.m), zm.loadMat(&proj.m));
}

/// Reads the first row of the light query, which the draw uses as the direction the light shines;
/// null when the query has no row.
fn lightDirOf(ctx: ?*abi_runtime.c.ke_system_ctx) ?zm.Vec {
    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);
    if (segc == 0 or segs.?[0].count == 0) return null;
    const dl: *const abi_render_components.c.ke_directional_light_component = @ptrCast(@alignCast(segs.?[0].columns.?[0]));
    return zm.f32x4(dl.direction.x, dl.direction.y, dl.direction.z, 0.0);
}

inline fn moduleOf(user: ?*anyopaque) *ShadowModule {
    return @alignCast(@ptrCast(user.?));
}

/// The render-phase body that `setup` registers as "render.shadow". It succeeds on the early exits
/// for a missing light or a pass that cannot begin, and fails with the code of the call that
/// failed when the per-object uniforms cannot grow. It uploads an orthographic light view-projection built from the light's
/// direction to the light buffer of its group, then draws every mesh with a world transform into
/// the group's map, the group's depth being its depth attachment. Each mesh
/// gets its own slot of the object uniform and is drawn at that slot's dynamic offset, until the
/// draw cap is reached.
fn system(ctx: ?*abi_runtime.c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const sh = moduleOf(user);
    const core = sh.core;

    const light_dir = lightDirOf(ctx) orelse return R.ok;

    const lvp = lightViewProj(sh.view_space, sh.ndc, sh.params, light_dir);
    var lvp_arr: [16]f32 = undefined;
    zm.storeMat(lvp_arr[0..], lvp);
    core.*.upload.?(core, sh.lvp_uniform, 0, &lvp_arr, 64);

    const pc = core.*.begin_pass.?(core, &sh.io);
    if (pc == null) return R.ok;

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 1, &segc);
    var mesh_total: usize = 0;
    for (segs.?[0..segc]) |seg| mesh_total += seg.count;
    const objects = &sh.objects.?;
    const grown = objects.ensure(@intCast(mesh_total));
    if (grown != R.ok) {
        core.*.end_pass.?(core, pc);
        return grown;
    }

    const rp = pc.?.begin_render.?(pc);
    rp.?.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &sh.pipeline_params));
    sh.binder.bind_render_set.?(sh.binder, rp, sh.light_set, null, 0);

    var draw_idx: u32 = 0;
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const meshes: [*c]const abi_render_components.c.ke_mesh_component = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
        const wts: [*c]const abi_spatial.c.ke_world_transform_component = @ptrCast(@alignCast(segs.?[s].columns.?[1]));
        var i: usize = 0;
        while (i < segs.?[s].count) : (i += 1) {
            var vbo: abi_asset_resolver.c.ke_gpu_buffer = 0;
            var ibo: abi_asset_resolver.c.ke_gpu_buffer = 0;
            var idx_count: u32 = 0;
            if (!core.*.mesh_buffers.?(core, meshes[i].mesh, &vbo, &ibo, &idx_count)) continue;

            var u: ShadowObj = undefined;
            @memcpy(u.model[0..], wts[i].matrix.m[0..16]);
            const offset: u32 = Objects.offset(draw_idx);
            core.*.upload.?(core, objects.buffer, offset, &u, @sizeOf(ShadowObj));

            objects.bind(rp, draw_idx);
            rp.?.set_vertex_buffer.?(rp, 0, vbo, 0);
            rp.?.set_index_buffer.?(rp, ibo, abi_render_gpu.c.KE_GPU_INDEX_FORMAT_UINT16, 0);
            rp.?.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
            draw_idx += 1;
        }
    }
    rp.?.end.?(rp);
    core.*.end_pass.?(core, pc);
    return R.ok;
}

/// Called once by `ke_render_shadow_create`. It resolves the parameters, copies the group's names,
/// creates and publishes the light uniform, declares the map and its depth, loads the shaders, builds the pipeline, bind groups and per object uniform, and
/// fills the access list and the queries. A step that fails fails with the code of the render
/// service or the device, and leaves the handles created before it stored in the module, for
/// `destroyModule` to release; a pipeline that cannot be created fails as not initialized.
fn setup(sh: *ShadowModule, p: *const abi_render_shadow_factory.c.ke_render_shadow_params) R.Error!void {
    const core: *abi_render.c.ke_render_service = p.service.?;
    const dev: *abi_render_gpu.c.ke_gpu_device = p.device.?;
    const mesh_cid = p.scene.?.component_ids.?(p.scene).?.mesh;
    const world_transform_cid = p.scene.?.component_ids.?(p.scene).?.world_transform;
    const light_cid = p.scene.?.component_ids.?(p.scene).?.directional_light;
    const frame_cid = p.frame.?.frame_cid.?(p.frame);
    sh.core = core;
    sh.device = dev;
    sh.ndc = p.device.?.get_ndc_convention.?(p.device);
    sh.view_space = p.view_space.?;
    sh.params = shapeOf(p);
    sh.mesh_cid = mesh_cid;
    sh.world_transform_cid = world_transform_cid;
    sh.light_cid = light_cid;
    sh.frame_cid = frame_cid;

    const group = std.mem.span(p.output.?);
    sh.names[0] = gpa.dupeZ(u8, group) catch return error.OutOfMemory;
    sh.names[1] = std.fmt.allocPrintSentinel(gpa, "{s}{s}", .{ group, abi_render_contract.c.KE_RENDER_SHADOW_DEPTH }, 0) catch return error.OutOfMemory;
    sh.names[2] = std.fmt.allocPrintSentinel(gpa, "{s}{s}", .{ group, abi_render_contract.c.KE_RENDER_SHADOW_LIGHT }, 0) catch return error.OutOfMemory;
    const map_name = sh.names[0].?.ptr;
    const depth_name = sh.names[1].?.ptr;

    try R.check(dev.create_buffer.?(dev, &abi_render_gpu.c.ke_gpu_buffer_params{ .label = "shadow.lvp_uniform", .initial_data = null, .size = 64, .usage = abi_render_gpu.c.KE_GPU_BUFFER_USAGE_UNIFORM | abi_render_gpu.c.KE_GPU_BUFFER_USAGE_COPY_DST, .mapped_at_creation = false }, &sh.lvp_uniform));
    var light_cid_out: abi_asset_resolver.c.ke_component_id = undefined;
    try R.check(core.*.import_buffer.?(core, sh.names[2].?.ptr, sh.lvp_uniform, 64, &light_cid_out));

    var shadow_map_cid: abi_asset_resolver.c.ke_component_id = undefined;
    try R.check(core.*.declare.?(core, &abi_render.c.ke_render_resource_params{
        .name = map_name,
        .type = abi_render.c.KE_RENDER_RESOURCE_TEXTURE,
        .format = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT,
        .size_mode = abi_render.c.KE_RENDER_SIZE_ABSOLUTE,
        .width = sh.params.resolution,
        .height = sh.params.resolution,
        .scale_x = 1.0,
        .scale_y = 1.0,
        .clear_value = .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
    }, &shadow_map_cid));
    var shadow_depth_cid: abi_asset_resolver.c.ke_component_id = undefined;
    try R.check(core.*.declare.?(core, &abi_render.c.ke_render_resource_params{
        .name = depth_name,
        .type = abi_render.c.KE_RENDER_RESOURCE_TEXTURE,
        .format = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
        .size_mode = abi_render.c.KE_RENDER_SIZE_ABSOLUTE,
        .width = sh.params.resolution,
        .height = sh.params.resolution,
        .scale_x = 1.0,
        .scale_y = 1.0,
    }, &shadow_depth_cid));
    sh.view = core.*.resource_view.?(core, map_name);

    var sh_vs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "shadow", abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX, &sh_vs));
    var sh_fs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "shadow", abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT, &sh_fs));

    sh.binder = core.*.resource_binder.?(core).?;
    try R.check(sh.binder.create_shader_layout.?(sh.binder, &shader_layout, &sh.layout));

    const sh_attr = abi_render_gpu.c.ke_gpu_vertex_attribute{ .shader_location = 0, .format = abi_render_gpu.c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 };
    const sh_vbl = abi_render_gpu.c.ke_gpu_vertex_buffer_layout{ .stride = 11 * @sizeOf(f32), .step_mode = abi_render_gpu.c.KE_GPU_VERTEX_STEP_MODE_VERTEX, .attribute_count = 1, .attributes = (&sh_attr)[0..1] };
    var shp = std.mem.zeroes(abi_render_gpu.c.ke_gpu_render_pipeline_params);
    shp.label = "shadow.pipeline";
    shp.vertex_module = sh_vs;
    shp.fragment_module = sh_fs;
    shp.vertex_entry = "vs_main";
    shp.fragment_entry = "fs_main";
    shp.primitive_topology = abi_render_gpu.c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    shp.cull_mode = abi_render_gpu.c.KE_GPU_CULL_MODE_NONE;
    shp.front_face = abi_render_gpu.c.KE_GPU_FRONT_FACE_CCW;
    shp.vertex_buffer_count = 1;
    shp.vertex_buffers = (&sh_vbl)[0..1];
    shp.blend_state.write_mask = 0x0F;
    shp.depth_stencil.depth_test_enabled = true;
    shp.depth_stencil.depth_write_enabled = true;
    shp.depth_stencil.depth_compare = abi_render_gpu.c.KE_GPU_COMPARE_LESS;
    try R.check(sh.binder.pipeline_layouts.?(sh.binder, sh.layout, &shp.bind_group_layouts, shp.bind_group_layouts.len, &shp.bind_group_layout_count));
    shp.color_target_formats[0] = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
    shp.color_target_count = 1;
    sh.pipeline_params = shp;
    if (core.*.get_or_create_pipeline.?(core, &sh.pipeline_params) == abi_render_gpu.c.KE_GPU_INVALID_HANDLE) {
        log.warn("shadow pass: render pipeline creation failed", .{});
        return error.NotInitialized;
    }

    const light_binding = [_]abi_render_gpu.c.ke_render_shader_binding{
        .{ .name = "light", .buffer = sh.lvp_uniform, .buffer_offset = 0, .buffer_size = 64, .texture_view = 0, .sampler = 0 },
    };
    try R.check(sh.binder.create_set.?(sh.binder, sh.layout, null, "shadow.light_set", &light_binding, light_binding.len, &sh.light_set));

    sh.objects = .{ .device = dev, .binder = sh.binder, .layout = sh.layout, .buffer_label = "shadow.obj_uniform", .set_label = "shadow.obj_set" };
    try R.check(sh.objects.?.ensure(1));

    sh.writes = .{ map_name, depth_name };
    sh.io = std.mem.zeroes(abi_render.c.ke_render_pass_io);
    sh.io.name = "render.shadow";
    sh.io.writes = @ptrCast(&sh.writes);
    sh.io.writes_count = 2;
    sh.access = .{
        .{ .cid = shadow_map_cid, .access = abi_runtime.c.KE_ACCESS_WRITE },
        .{ .cid = shadow_depth_cid, .access = abi_runtime.c.KE_ACCESS_WRITE },
        .{ .cid = mesh_cid, .access = abi_runtime.c.KE_ACCESS_READ },
        .{ .cid = world_transform_cid, .access = abi_runtime.c.KE_ACCESS_READ },
        .{ .cid = light_cid, .access = abi_runtime.c.KE_ACCESS_READ },
        .{ .cid = frame_cid, .access = abi_runtime.c.KE_ACCESS_READ },
    };

    const rd = abi_runtime.c.KE_ACCESS_READ;
    sh.queries_terms = .{ .{ .cid = light_cid, .access = rd }, .{ .cid = mesh_cid, .access = rd }, .{ .cid = world_transform_cid, .access = rd } };
    sh.queries = .{ .{ .terms = sh.queries_terms[0..].ptr, .term_count = 1 }, .{ .terms = sh.queries_terms[1..].ptr, .term_count = 2 } };
}

/// Called after a failed `setup` and by `destroyHandle`. It releases only the GPU objects that were
/// created, and leaves freeing the module to its caller.
fn destroyModule(sh: *ShadowModule) void {
    for (sh.names) |name| if (name) |n| gpa.free(n);
    const dev = sh.device;
    if (sh.objects) |*objects| objects.release();
    if (sh.lvp_uniform != abi_render_gpu.c.KE_GPU_INVALID_HANDLE) dev.destroy_buffer.?(dev, sh.lvp_uniform);
    if (sh.layout == abi_render_gpu.c.KE_RENDER_BINDING_INVALID) return;
    sh.binder.destroy_set.?(sh.binder, sh.light_set);
    sh.binder.destroy_shader_layout.?(sh.binder, sh.layout);
}

/// The `destroy` slot of the handle `ke_render_shadow_create` returns. It is the only path that
/// frees a module whose creation succeeded.
fn destroyHandle(self: ?*abi_render_shadow_factory.c.ke_render_shadow) callconv(.c) void {
    const sh: *ShadowModule = @ptrCast(@alignCast(self orelse return));
    _ = sh.runtime.unregister_system.?(sh.runtime, sh.system);
    destroyModule(sh);
    gpa.destroy(sh);
}

/// A missing runtime, service, device, view space or output fails as an invalid argument and a
/// module that cannot be allocated as out of memory; a failing `setup` or a runtime refusing the
/// system fails with its code and leaves the handle zeroed, and every such path frees the module.
export fn ke_render_shadow_create(params_in: ?*const abi_render_shadow_factory.c.ke_render_shadow_params, out_shadow: [*c]abi_render_shadow_factory.c.ke_render_shadow_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_shadow orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const p = params_in orelse return R.code(error.InvalidArgument);
    const rt: *abi_runtime.c.ke_runtime = p.runtime orelse return R.code(error.InvalidArgument);
    if (p.scene == null or p.frame == null or p.service == null or p.device == null or p.view_space == null or p.output == null) return R.code(error.InvalidArgument);

    const sh = gpa.create(ShadowModule) catch |err| return R.code(err);
    sh.* = .{};
    setup(sh, p) catch |err| {
        destroyModule(sh);
        gpa.destroy(sh);
        return R.code(err);
    };

    var sys_params = std.mem.zeroes(abi_runtime.c.ke_runtime_system_params);
    sys_params.name = "render.shadow";
    sys_params.phase = abi_runtime.c.KE_PHASE_RENDER;
    sys_params.queries = &sh.queries;
    sys_params.query_count = sh.queries.len;
    sys_params.access_list = &sh.access;
    sys_params.access_count = sh.access.len;
    sys_params.user_data = sh;
    sys_params.execute = system;
    var system_id: abi_framework.c.ke_system_id = 0;
    const registered = rt.register_system.?(rt, &sys_params, &system_id);
    if (registered != R.ok) {
        destroyModule(sh);
        gpa.destroy(sh);
        return registered;
    }
    sh.runtime = rt;
    sh.system = system_id;

    out.* = .{ .ref = @ptrCast(sh), .destroy = destroyHandle };
    return R.ok;
}

const testing = std.testing;

const test_ids = std.mem.zeroInit(abi_render.c.ke_render_scene_component_ids, .{ .mesh = 1, .camera = 2, .directional_light = 3, .point_light = 4, .spot_light = 5, .ambient_light = 6, .skybox = 7, .sprite2d = 8, .label = 9, .world_transform = 10 });

fn testComponentIds(_: [*c]abi_render.c.ke_render_scene_resolve) callconv(.c) [*c]const abi_render.c.ke_render_scene_component_ids {
    return &test_ids;
}

var test_scene: abi_render.c.ke_render_scene_resolve = .{ .handle = null, .component_ids = testComponentIds };

fn testFrameCid(_: [*c]abi_render.c.ke_render_frame) callconv(.c) abi_render.c.ke_component_id {
    return 11;
}

var test_frame: abi_render.c.ke_render_frame = .{ .handle = null, .frame_cid = testFrameCid };


const zsub = @import("zsub");

const Rig = struct {
    dev: zsub.For(abi_render_gpu.c.ke_gpu_device),
    binder: zsub.For(abi_render_gpu.c.ke_render_resource_binder),
    core: zsub.For(abi_render.c.ke_render_service),
    rt: zsub.For(abi_runtime.c.ke_runtime),

    fn init(self: *Rig) !void {
        try self.dev.init();
        _ = self.dev.when(.create_buffer).writesFresh(2);
        try self.binder.init();
        _ = self.binder.when(.create_shader_layout).writesFresh(2);
        _ = self.binder.when(.create_set).writesFresh(6);
        try self.core.init();
        _ = self.core.when(.resource_binder).returns(self.binder.api());
        _ = self.core.when(.load_shader).writesFresh(3);
        _ = self.core.when(.get_or_create_pipeline).returnsFresh();
        _ = self.core.when(.cid).returnsFresh();
        _ = self.core.when(.declare).writesFresh(2);
        _ = self.core.when(.import_buffer).writesFresh(4);
        _ = self.core.when(.resource_view).returnsFresh();
        _ = self.core.when(.texture_view).returnsFresh();
        try self.rt.init();
        _ = self.rt.when(.register_system).writesFresh(2);
    }

    fn deinit(self: *Rig) void {
        self.rt.deinit();
        self.core.deinit();
        self.binder.deinit();
        self.dev.deinit();
    }

    fn expectReleased(self: *Rig) !void {
        try self.dev.received(.destroy_buffer).where(zsub.argIsNot(1, abi_render_gpu.c.KE_GPU_INVALID_HANDLE)).sameAs(self.dev.received(.create_buffer));
        try self.binder.received(.destroy_shader_layout).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_shader_layout));
        try self.binder.received(.destroy_set).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_set));
    }
};

test "creating and destroying the shadow pass leaves no block allocated and no GPU resource live" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var view_space = std.mem.zeroes(abi_view.c.ke_view_space);
    var h: abi_render_shadow_factory.c.ke_render_shadow_handle = undefined;
    try R.check(ke_render_shadow_create(&.{ .scene = &test_scene, .frame = &test_frame, .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .view_space = &view_space, .output = "shadow" }, &h));
    h.destroy.?(h.ref);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}

test "destroying the shadow pass unregisters every system it registered" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var view_space = std.mem.zeroes(abi_view.c.ke_view_space);
    var h: abi_render_shadow_factory.c.ke_render_shadow_handle = undefined;
    try R.check(ke_render_shadow_create(&.{ .scene = &test_scene, .frame = &test_frame, .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .view_space = &view_space, .output = "shadow" }, &h));
    h.destroy.?(h.ref);
    try rig.rt.received(.register_system).atLeast(1);
    try rig.rt.received(.unregister_system).where(zsub.argIs(1, @as(abi_framework.c.ke_system_id, 0))).never();
    try rig.rt.received(.unregister_system).sameAs(rig.rt.received(.register_system));
}

test "a shadow pass whose shader fails to load releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.core.when(.load_shader).returns(abi_result.c.KE_RESULT_GENERAL);
    var view_space = std.mem.zeroes(abi_view.c.ke_view_space);
    var h: abi_render_shadow_factory.c.ke_render_shadow_handle = undefined;
    try testing.expect(ke_render_shadow_create(&.{ .scene = &test_scene, .frame = &test_frame, .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .view_space = &view_space, .output = "shadow" }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}

test "a missing frame is refused" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var view_space = std.mem.zeroes(abi_view.c.ke_view_space);
    var h: abi_render_shadow_factory.c.ke_render_shadow_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_shadow_create(&.{ .scene = &test_scene, .frame = null, .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .view_space = &view_space, .output = "shadow" }, &h)));
}

test "a missing scene is refused" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var view_space = std.mem.zeroes(abi_view.c.ke_view_space);
    var h: abi_render_shadow_factory.c.ke_render_shadow_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_shadow_create(&.{ .scene = null, .frame = &test_frame, .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .view_space = &view_space, .output = "shadow" }, &h)));
}

test "a shadow pass the runtime refuses to register releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.rt.when(.register_system).returns(abi_result.c.KE_RESULT_OUT_OF_MEMORY);
    var view_space = std.mem.zeroes(abi_view.c.ke_view_space);
    var h: abi_render_shadow_factory.c.ke_render_shadow_handle = undefined;
    try testing.expect(ke_render_shadow_create(&.{ .scene = &test_scene, .frame = &test_frame, .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .view_space = &view_space, .output = "shadow" }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}
