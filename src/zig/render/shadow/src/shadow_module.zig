//! The shadow pass: the systems that publish a depth map seen from the directional light and the
//! light matrix, and declare at the prepass stage the pass drawing the meshes of the scene into that
//! map. It also owns the creation and teardown of that pass, behind the one factory it exports.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_components = @import("abi_render_components");
const abi_render_gpu = @import("abi_render_gpu");
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_shadow").logFn };

const zm = @import("zmath");
const abi_ecs = @import("abi_ecs");
const abi_math = @import("abi_math");
const abi_part = @import("abi_part");
const abi_render = @import("abi_render");
const abi_render_frame = @import("abi_render_frame");
const abi_render_graph = @import("abi_render_graph");
const abi_render_shadow_factory = @import("abi_render_shadow_factory");
const abi_result = @import("abi_result");
const abi_settings = @import("abi_settings");
const settings_schema = @import("settings_schema");
const abi_schedule = @import("abi_schedule");
const abi_spatial = @import("abi_spatial");
const abi_view = @import("abi_view");
const hooked_systems = @import("hooked_systems");
const R = @import("result").Result(.{});
const log = std.log.scoped(.render_shadow);

const heap = @import("heap");
const gpa = heap.gpa;
const rg = abi_render_graph.c;

/// The shape of the shadow map: the pass's settings, with this implementation's defaults.
const Shape = struct {
    resolution: u32 = 1024,
    light_distance: f32 = 25.0,
    extent: f32 = 20.0,
    near_plane: f32 = 0.1,
    far_plane: f32 = 50.0,

    pub const ranges = .{ .resolution = .{ 1, 16384 }, .extent = .{ std.math.floatMin(f64), std.math.floatMax(f64) }, .near_plane = .{ 0.0, std.math.floatMax(f64) } };
};

/// A near plane not before the far one is refused, beside what the schema refuses.
fn shapeOf(settings: *abi_settings.c.ke_settings) R.Error!Shape {
    const shape = try settings_schema.read(Shape, settings);
    if (!(shape.near_plane < shape.far_plane)) {
        log.warn("shadow pass: near plane {d} is not before far plane {d}", .{ shape.near_plane, shape.far_plane });
        return error.InvalidArgument;
    }
    return shape;
}

const ShadowObj = extern struct { model: [16]f32 };

const Objects = @import("object_uniforms").ObjectUniforms(ShadowObj);

const object_hint = [_]abi_render_gpu.c.ke_render_binding_hint{.{ .name = "object", .flags = abi_render_gpu.c.KE_RENDER_BINDING_HINT_DYNAMIC_OFFSET }};

const shader_layout = abi_render_gpu.c.ke_render_shader_layout_desc{
    .shader = "shadow",
    .stages = abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX | abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT,
    .hints = &object_hint,
    .hint_count = object_hint.len,
};

/// One draw `queueSystem` prepared and `record` issues.
const Prepared = struct { vbo: abi_asset_resolver.c.ke_gpu_buffer, ibo: abi_asset_resolver.c.ke_gpu_buffer, index_count: u32, slot: u32 };

/// The state of one shadow pass, allocated by `ke_render_shadow_create` and freed by
/// `destroyOwner` after it unregisters `systems`. Fields that `setup` has not reached keep their
/// initial values, so `destroyModule` releases only what exists. `map`, `depth` and `light` are the
/// frame's, made by `prepareSystem` when a light is in the render world; `prepared` is rebuilt by
/// `queueSystem` and read by `record`.
const ShadowModule = struct {
    systems: hooked_systems.Systems(2) = .{},
    core: *abi_render.c.ke_render_service = undefined,
    device: *abi_render_gpu.c.ke_gpu_device = undefined,
    frame: *abi_render_frame.c.ke_render_frame = undefined,
    ndc: abi_render_gpu.c.ke_ndc_convention = undefined,
    view_space: *abi_view.c.ke_view_space = undefined,
    params: Shape = undefined,
    map: rg.ke_render_graph_resource = rg.KE_RENDER_GRAPH_RESOURCE_INVALID,
    depth: rg.ke_render_graph_resource = rg.KE_RENDER_GRAPH_RESOURCE_INVALID,
    light: rg.ke_render_graph_resource = rg.KE_RENDER_GRAPH_RESOURCE_INVALID,

    pipeline_params: abi_render_gpu.c.ke_gpu_render_pipeline_desc = undefined,
    lvp_uniform: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    binder: *abi_render_gpu.c.ke_render_resource_binder = undefined,
    layout: abi_asset_resolver.c.ke_render_shader_layout = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    light_set: abi_asset_resolver.c.ke_render_resource_set = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    objects: ?Objects = null,
    prepared: std.ArrayList(Prepared) = .empty,

    access: [1]abi_ecs.c.ke_ecs_query_term = undefined,
    queries_terms: [3]abi_ecs.c.ke_ecs_query_term = undefined,
    queries: [2]abi_ecs.c.ke_ecs_query_desc = undefined,
};

/// Called by `queueSystem` each frame with the direction it read from the directional light. The result
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
fn lightDirOf(ctx: ?*abi_schedule.c.ke_schedule_ctx) ?zm.Vec {
    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);
    if (segc == 0 or segs.?[0].count == 0) return null;
    const dl: *const abi_render_components.c.ke_directional_light_component = @ptrCast(@alignCast(segs.?[0].columns.?[0]));
    return zm.f32x4(dl.direction.x, dl.direction.y, dl.direction.z, 0.0);
}

inline fn moduleOf(user: ?*anyopaque) *ShadowModule {
    return @alignCast(@ptrCast(user.?));
}

fn mapTexture(graph: *rg.ke_render_graph, name: [*:0]const u8, format: abi_render_gpu.c.ke_gpu_texture_format, size: u32, out: *rg.ke_render_graph_resource) abi_result.c.ke_result {
    var desc = std.mem.zeroes(rg.ke_render_graph_texture_desc);
    desc.name = name;
    desc.format = format;
    desc.size_class = rg.KE_RENDER_GRAPH_SIZE_ABSOLUTE;
    desc.width = size;
    desc.height = size;
    desc.mip_levels = 1;
    desc.array_layers = 1;
    desc.samples = 1;
    return graph.create_texture.?(graph, &desc, out);
}

/// "render.shadow.map", in the render prepare set: when a frame is being declared and a directional
/// light is in the render world, makes the map and its depth, imports the light buffer, and
/// publishes the map and the light. Otherwise nothing is published, and readers meet the neutral
/// shadow. The graph or the frame refusing one fails with its code.
fn prepareSystem(ctx: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const sh = moduleOf(user);
    const frame = sh.frame;
    sh.map = rg.KE_RENDER_GRAPH_RESOURCE_INVALID;
    if (!frame.live.?(frame)) return R.ok;
    if (lightDirOf(ctx) == null) return R.ok;
    const graph = frame.graph.?(frame).?;
    var made = mapTexture(graph, "shadow.map", abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT, sh.params.resolution, &sh.map);
    if (made == R.ok) made = mapTexture(graph, "shadow.depth", abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT, sh.params.resolution, &sh.depth);
    if (made == R.ok) made = graph.import_buffer.?(graph, sh.lvp_uniform, 64, &sh.light);
    if (made == R.ok) made = frame.publish.?(frame, abi_render.c.KE_RENDER_RESOURCE_SHADOW_MAP, sh.map);
    if (made == R.ok) made = frame.publish.?(frame, abi_render.c.KE_RENDER_RESOURCE_SHADOW_LIGHT, sh.light);
    if (made != R.ok) sh.map = rg.KE_RENDER_GRAPH_RESOURCE_INVALID;
    return made;
}

/// Records the draws `queueSystem` prepared into the map, each at its slot's dynamic offset.
fn record(user: ?*anyopaque, ctx: ?*rg.ke_render_graph_ctx) callconv(.c) abi_result.c.ke_result {
    const sh = moduleOf(user);
    const core = sh.core;
    const rp: [*c]abi_render_gpu.c.ke_gpu_render_pass = @ptrCast(ctx.?.render_pass.?(ctx));
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &sh.pipeline_params));
    sh.binder.bind_render_set.?(sh.binder, rp, sh.light_set, null, 0);
    const objects = &sh.objects.?;
    for (sh.prepared.items) |d| {
        objects.bind(rp, d.slot);
        rp.*.set_vertex_buffer.?(rp, 0, d.vbo, 0);
        rp.*.set_index_buffer.?(rp, d.ibo, abi_render_gpu.c.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.*.draw_indexed.?(rp, d.index_count, 1, 0, 0, 0);
    }
    return R.ok;
}

/// "render.shadow", in the render queue set. With no map made this frame it declares nothing.
/// Otherwise it uploads an orthographic light view-projection built from the light's direction,
/// gives every mesh with a world transform its own slot of the object uniform, and declares at
/// KE_RENDER_STAGE_PREPASS the pass clearing and drawing the map, its depth being the depth
/// attachment. It fails with the code of the call that failed when the per-object uniforms cannot
/// grow or the graph refuses the pass.
fn queueSystem(ctx: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const sh = moduleOf(user);
    const core = sh.core;
    if (sh.map == rg.KE_RENDER_GRAPH_RESOURCE_INVALID) return R.ok;
    const light_dir = lightDirOf(ctx) orelse return R.ok;

    var lvp_arr: [16]f32 = undefined;
    zm.storeMat(lvp_arr[0..], lightViewProj(sh.view_space, sh.ndc, sh.params, light_dir));
    core.*.upload.?(core, sh.lvp_uniform, 0, &lvp_arr, 64);

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 1, &segc);
    var mesh_total: usize = 0;
    if (segc > 0) for (segs.?[0..segc]) |s| {
        mesh_total += s.count;
    };
    const objects = &sh.objects.?;
    const grown = objects.ensure(@intCast(mesh_total));
    if (grown != R.ok) return grown;
    sh.prepared.clearRetainingCapacity();
    var slot: u32 = 0;
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
            core.*.upload.?(core, objects.buffer, Objects.offset(slot), &u, @sizeOf(ShadowObj));
            sh.prepared.append(gpa, .{ .vbo = vbo, .ibo = ibo, .index_count = idx_count, .slot = slot }) catch return R.code(error.OutOfMemory);
            slot += 1;
        }
    }

    var uses = std.mem.zeroes([3]rg.ke_render_graph_use);
    uses[0].resource = sh.map;
    uses[0].usage = rg.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT;
    uses[0].load = rg.KE_RENDER_GRAPH_LOAD_CLEAR;
    uses[0].clear_color = .{ 1.0, 1.0, 1.0, 1.0 };
    uses[1].resource = sh.depth;
    uses[1].usage = rg.KE_RENDER_GRAPH_USAGE_DEPTH_WRITE;
    uses[1].load = rg.KE_RENDER_GRAPH_LOAD_CLEAR;
    uses[1].clear_depth = 1.0;
    uses[2].resource = sh.light;
    uses[2].usage = rg.KE_RENDER_GRAPH_USAGE_UNIFORM;
    var desc = std.mem.zeroes(rg.ke_render_graph_pass_desc);
    desc.name = "render.shadow";
    desc.type = rg.KE_RENDER_GRAPH_PASS_RASTER;
    desc.injection_point = abi_render.c.KE_RENDER_STAGE_PREPASS;
    desc.uses = &uses;
    desc.use_count = uses.len;
    desc.record = record;
    desc.user = sh;
    const graph = sh.frame.graph.?(sh.frame).?;
    var pass: rg.ke_render_graph_pass = 0;
    return graph.add_pass.?(graph, &desc, &pass);
}

/// Called once by `ke_render_shadow_create`. It resolves the parameters, creates the light uniform,
/// loads the shaders, builds the pipeline, bind groups and per object uniform, and fills the access
/// list and the queries over the render world. A step that fails fails with the code of the render
/// service or the device, and leaves the handles created before it stored in the module, for
/// `destroyModule` to release; a pipeline that cannot be created fails as not initialized.
fn setup(sh: *ShadowModule, service: *abi_render.c.ke_render_service, device: *abi_render_gpu.c.ke_gpu_device, frame: *abi_render_frame.c.ke_render_frame, scene: *abi_render.c.ke_render_scene_resolve, view_space: *abi_view.c.ke_view_space, settings: *abi_settings.c.ke_settings) R.Error!void {
    const core: *abi_render.c.ke_render_service = service;
    const dev: *abi_render_gpu.c.ke_gpu_device = device;
    const ids = scene.render_component_ids.?(scene).?;
    sh.core = core;
    sh.device = dev;
    sh.frame = frame;
    sh.ndc = dev.get_ndc_convention.?(dev);
    sh.view_space = view_space;
    sh.params = try shapeOf(settings);

    try R.check(dev.create_buffer.?(dev, &abi_render_gpu.c.ke_gpu_buffer_desc{ .label = "shadow.lvp_uniform", .initial_data = null, .size = 64, .usage = abi_render_gpu.c.KE_GPU_BUFFER_USAGE_UNIFORM | abi_render_gpu.c.KE_GPU_BUFFER_USAGE_COPY_DST, .mapped_at_creation = false }, &sh.lvp_uniform));

    var sh_vs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "shadow", abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX, &sh_vs));
    var sh_fs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "shadow", abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT, &sh_fs));

    sh.binder = core.*.resource_binder.?(core).?;
    try R.check(sh.binder.create_shader_layout.?(sh.binder, &shader_layout, &sh.layout));

    const sh_attr = abi_render_gpu.c.ke_gpu_vertex_attribute{ .shader_location = 0, .format = abi_render_gpu.c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 };
    const sh_vbl = abi_render_gpu.c.ke_gpu_vertex_buffer_layout{ .stride = 11 * @sizeOf(f32), .step_mode = abi_render_gpu.c.KE_GPU_VERTEX_STEP_MODE_VERTEX, .attribute_count = 1, .attributes = (&sh_attr)[0..1] };
    var shp = std.mem.zeroes(abi_render_gpu.c.ke_gpu_render_pipeline_desc);
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

    sh.access = .{.{ .component = sh.frame.frame_cid.?(sh.frame), .access = abi_ecs.c.KE_ECS_ACCESS_WRITE }};
    const rd = abi_ecs.c.KE_ECS_ACCESS_READ;
    sh.queries_terms = .{ .{ .component = ids.*.directional_light, .access = rd }, .{ .component = ids.*.mesh, .access = rd }, .{ .component = ids.*.world_transform, .access = rd } };
    sh.queries = .{ .{ .terms = sh.queries_terms[0..].ptr, .term_count = 1 }, .{ .terms = sh.queries_terms[1..].ptr, .term_count = 2 } };
}

/// Called after a failed `setup` and by `destroyOwner`. It releases only the GPU objects that were
/// created, and leaves freeing the module to its caller.
fn destroyModule(sh: *ShadowModule) void {
    const dev = sh.device;
    if (sh.objects) |*objects| objects.release();
    sh.prepared.deinit(gpa);
    if (sh.lvp_uniform != abi_render_gpu.c.KE_GPU_INVALID_HANDLE) dev.destroy_buffer.?(dev, sh.lvp_uniform);
    if (sh.layout == abi_render_gpu.c.KE_RENDER_BINDING_INVALID) return;
    sh.binder.destroy_set.?(sh.binder, sh.light_set);
    sh.binder.destroy_shader_layout.?(sh.binder, sh.layout);
}

/// The `destroy` of the owner `ke_render_shadow_create` hands out: unregisters the systems, releases the GPU
/// objects and frees the pass; a null argument is ignored.
fn destroyOwner(ref: ?*anyopaque) callconv(.c) void {
    const sh: *ShadowModule = @ptrCast(@alignCast(ref orelse return));
    sh.systems.unregister();
    destroyModule(sh);
    gpa.destroy(sh);
}

/// The factory declared in shadow_create.h. A missing scene, frame, service, device, view space or
/// settings fails as an invalid argument and a module that cannot be allocated as out of memory; a
/// failing `setup` fails with its code and leaves the handle zeroed, and every such path frees the
/// module.
export fn ke_render_shadow_create(
    service_in: ?*abi_render.c.ke_render_service,
    device_in: ?*abi_render_gpu.c.ke_gpu_device,
    frame_in: ?*abi_render_frame.c.ke_render_frame,
    scene_in: ?*abi_render.c.ke_render_scene_resolve,
    view_space_in: ?*abi_view.c.ke_view_space,
    render_prepare: ?*abi_schedule.c.ke_schedule,
    render_prepare_set: abi_schedule.c.ke_schedule_set_id,
    render_queue: ?*abi_schedule.c.ke_schedule,
    render_queue_set: abi_schedule.c.ke_schedule_set_id,
    settings: ?*abi_settings.c.ke_settings,
    out_pass: ?*abi_part.c.ke_owner,
) callconv(.c) abi_result.c.ke_result {
    const out = out_pass orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const service = service_in orelse return R.code(error.InvalidArgument);
    const device = device_in orelse return R.code(error.InvalidArgument);
    const frame = frame_in orelse return R.code(error.InvalidArgument);
    const scene = scene_in orelse return R.code(error.InvalidArgument);
    const view_space = view_space_in orelse return R.code(error.InvalidArgument);
    if (render_prepare == null) return R.code(error.InvalidArgument);
    if (render_queue == null) return R.code(error.InvalidArgument);
    const given = settings orelse {
        log.warn("shadow pass: no settings", .{});
        return R.code(error.InvalidArgument);
    };
    const sh = gpa.create(ShadowModule) catch |err| return R.code(err);
    sh.* = .{};
    setup(sh, service, device, frame, scene, view_space, given) catch |err| {
        destroyModule(sh);
        gpa.destroy(sh);
        return R.code(err);
    };
    const registered = sh.systems.register(.{
        .{ .name = "render.shadow.map", .execute = prepareSystem, .user = sh, .hook = 0, .queries = sh.queries[0..1], .access = &sh.access },
        .{ .name = "render.shadow", .execute = queueSystem, .user = sh, .hook = 1, .queries = &sh.queries, .access = &sh.access },
    }, &.{ .{ .schedule = render_prepare, .set = render_prepare_set }, .{ .schedule = render_queue, .set = render_queue_set } });
    if (registered != R.ok) {
        destroyModule(sh);
        gpa.destroy(sh);
        return registered;
    }
    out.* = .{ .ref = sh, .destroy = destroyOwner };
    return R.ok;
}

const testing = std.testing;
const zsub = @import("zsub");

const test_ids = std.mem.zeroInit(abi_render.c.ke_render_scene_component_ids, .{ .mesh = 1, .camera = 2, .directional_light = 3, .point_light = 4, .spot_light = 5, .ambient_light = 6, .skybox = 7, .sprite2d = 8, .label = 9, .world_transform = 10 });

fn testComponentIds(_: ?*abi_render.c.ke_render_scene_resolve) callconv(.c) ?*const abi_render.c.ke_render_scene_component_ids {
    return &test_ids;
}

var test_scene: abi_render.c.ke_render_scene_resolve = .{ .handle = null, .component_ids = testComponentIds, .render_component_ids = testComponentIds };

var test_light = std.mem.zeroInit(abi_render_components.c.ke_directional_light_component, .{ .direction = .{ .x = 0, .y = -1, .z = 0 } });
var light_columns = [_]?*anyopaque{@ptrCast(&test_light)};
var light_segment: abi_ecs.c.ke_ecs_segment = .{ .entities = null, .count = 1, .columns = &light_columns, .column_count = 1 };

fn lightView(_: ?*abi_schedule.c.ke_schedule_ctx, index: u32, out_count: ?*usize) callconv(.c) ?[*]const abi_ecs.c.ke_ecs_segment {
    out_count.?.* = if (index == 0) 1 else 0;
    return if (index == 0) (&light_segment)[0..1] else null;
}

var light_ctx: abi_schedule.c.ke_schedule_ctx = .{ .handle = null, .commands = null, .view = lightView, .slice = null };
var empty_ctx: abi_schedule.c.ke_schedule_ctx = .{ .handle = null, .commands = null, .view = noView, .slice = null };

fn noView(_: ?*abi_schedule.c.ke_schedule_ctx, _: u32, out_count: ?*usize) callconv(.c) ?[*]const abi_ecs.c.ke_ecs_segment {
    out_count.?.* = 0;
    return null;
}

/// The parts a pass is made of in a test.
const Rig = struct {
    dev: zsub.For(abi_render_gpu.c.ke_gpu_device),
    binder: zsub.For(abi_render_gpu.c.ke_render_resource_binder),
    core: zsub.For(abi_render.c.ke_render_service),
    schedule: zsub.For(abi_schedule.c.ke_schedule),
    frame: zsub.For(abi_render_frame.c.ke_render_frame),
    graph: zsub.For(rg.ke_render_graph),
    view_space: zsub.For(abi_view.c.ke_view_space),

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
        try self.schedule.init();
        _ = self.schedule.when(.register_system).writesFresh(2);
        try self.graph.init();
        _ = self.graph.when(.create_texture).writesFresh(2);
        _ = self.graph.when(.import_buffer).writesFresh(3);
        try self.view_space.init();
        try self.frame.init();
        _ = self.frame.when(.frame_cid).returns(11);
        _ = self.frame.when(.live).returns(true);
        _ = self.frame.when(.graph).returns(self.graph.api());
    }

    fn deinit(self: *Rig) void {
        self.frame.deinit();
        self.view_space.deinit();
        self.graph.deinit();
        self.schedule.deinit();
        self.core.deinit();
        self.binder.deinit();
        self.dev.deinit();
    }

    fn create(self: *Rig, settings: ?*abi_settings.c.ke_settings, out: *abi_part.c.ke_owner) abi_result.c.ke_result {
        return ke_render_shadow_create(self.core.api(), self.dev.api(), self.frame.api(), &test_scene, self.view_space.api(), self.schedule.api(), 4, self.schedule.api(), 5, settings, out);
    }

    fn expectReleased(self: *Rig) !void {
        try self.dev.received(.destroy_buffer).where(zsub.argIsNot(1, abi_render_gpu.c.KE_GPU_INVALID_HANDLE)).sameAs(self.dev.received(.create_buffer));
        try self.binder.received(.destroy_shader_layout).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_shader_layout));
        try self.binder.received(.destroy_set).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_set));
    }
};

var no_settings = settings_schema.Fixed.init(&.{});

fn passOf(h: abi_part.c.ke_owner) *ShadowModule {
    return @ptrCast(@alignCast(h.ref.?));
}

test "the shadow pass registers its two systems in its hooks, and destroying it unregisters them and releases the GPU objects" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_part.c.ke_owner = undefined;
    try R.check(rig.create(&no_settings.api, &h));
    try rig.schedule.received(.register_system).times(2);
    h.destroy.?(h.ref);
    try rig.schedule.received(.unregister_system).times(2);
    try rig.expectReleased();
}

test "a directional light gets a published map and light, and a shadow pass at the prepass stage" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_part.c.ke_owner = undefined;
    try R.check(rig.create(&no_settings.api, &h));
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, prepareSystem(&light_ctx, passOf(h), 0));
    try rig.frame.received(.publish).times(2);
    try testing.expectEqual(R.ok, queueSystem(&light_ctx, passOf(h), 0));
    try rig.graph.received(.add_pass).times(1);
}

test "a frame without a directional light publishes no shadow and declares no pass" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_part.c.ke_owner = undefined;
    try R.check(rig.create(&no_settings.api, &h));
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, prepareSystem(&empty_ctx, passOf(h), 0));
    try testing.expectEqual(R.ok, queueSystem(&empty_ctx, passOf(h), 0));
    try rig.frame.received(.publish).never();
    try rig.graph.received(.add_pass).never();
}

test "a shadow map with no texels is refused as an invalid argument" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
        var bad = settings_schema.Fixed.init(&.{.{ .key = "resolution", .value = .{ .int = 0 } }});
    var h: abi_part.c.ke_owner = undefined;
    try testing.expectError(error.InvalidArgument, R.check(rig.create(&bad.api, &h)));
    try testing.expect(h.ref == null);
    try rig.expectReleased();
}

test "a shadow pass whose shader fails to load releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.core.when(.load_shader).returns(abi_result.c.KE_RESULT_GENERAL);
    var h: abi_part.c.ke_owner = undefined;
    try testing.expect(rig.create(&no_settings.api, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
}

test "creating and destroying shadow passes leaves no block allocated" {
    try heap.expectNoLeaks();
}
