//! The cluster pass: the systems that gather the point and spot lights of a frame into GPU buffers,
//! publish each buffer in the frame under its own name, and declare at the prepass stage the compute
//! pass binning them into a view-space grid of clusters.

const abi_render_components = @import("abi_render_components");
const abi_render_gpu = @import("abi_render_gpu");
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_cluster").logFn };

const feature_bindings = @import("feature_bindings");
const cluster_buffers = feature_bindings.cluster_buffers;
const abi_ecs = @import("abi_ecs");
const abi_part = @import("abi_part");
const part = @import("part");
const abi_render = @import("abi_render");
const abi_render_cluster_factory = @import("abi_render_cluster_factory");
const abi_render_frame = @import("abi_render_frame");
const abi_render_graph = @import("abi_render_graph");
const abi_result = @import("abi_result");
const abi_settings = @import("abi_settings");
const settings_schema = @import("settings_schema");
const abi_schedule = @import("abi_schedule");
const abi_spatial = @import("abi_spatial");
const abi_view = @import("abi_view");
const hooked_systems = @import("hooked_systems");
const R = @import("result").Result(.{});
/// The pass's settings, with this implementation's defaults.
const Config = struct {
    grid_x: u32 = 16,
    grid_y: u32 = 9,
    grid_z: u32 = 24,
    max_lights_per_cluster: u32 = 64,

    pub const ranges = .{ .grid_x = .{ 1, 4096 }, .grid_y = .{ 1, 4096 }, .grid_z = .{ 1, 4096 }, .max_lights_per_cluster = .{ 1, 65536 } };
};

const heap = @import("heap");
const gpa = heap.gpa;
const rg = abi_render_graph.c;

const MAX_LIGHTS = 1_000_000;
const UPLOAD_CHUNK = 1024;

const PointLightGpu = extern struct {
    pos_radius: [4]f32,
    color_intensity: [4]f32,
};

const SpotLightGpu = extern struct {
    pos_range: [4]f32,
    dir_cos_inner: [4]f32,
    color_intensity: [4]f32,
    cone: [4]f32,
};

/// Mirrors the C spot light component, so the spot column is read through this layout, while the
/// point column is read through its C type.
const SpotLightComp = extern struct {
    dir: [3]f32,
    color: [3]f32,
    intensity: f32,
    range: f32,
    inner_deg: f32,
    outer_deg: f32,
};

const ClusterGridUniform = extern struct {
    cluster_grid: [4]f32,
    cluster_viewport: [4]f32,
    view_space: [4]f32,
};

const ClusterParams = extern struct {
    grid: [4]f32,
    counts: [4]f32,
    depth: [4]f32,
};

const cull_layout_params = abi_render_gpu.c.ke_render_shader_layout_desc{
    .shader = "cluster_cull",
    .stages = abi_render_gpu.c.KE_GPU_SHADER_STAGE_COMPUTE,
    .hints = null,
    .hint_count = 0,
};

/// A buffer the pass publishes, beside its size.
const Published = struct { buffer: abi_render.c.ke_gpu_buffer, size: usize };

/// The buffers the cull writes, by their index in `cluster_buffers`.
const written = [_]usize{ 2, 3, 4, 5 };

/// State of one cluster pass, allocated by `ke_render_cluster_create` and freed by `destroyOwner`
/// after it unregisters `systems`. The core, device, view space and camera are borrowed. The grid fields
/// are assigned by `setup`; the GPU fields are the invalid handle until their own creation succeeds.
/// `resources` are the published buffers of the frame, imported by `prepareSystem`.
const ClusterModule = struct {
    systems: hooked_systems.Systems(2) = .{},
    core: *abi_render.c.ke_render_service = undefined,
    device: *abi_render_gpu.c.ke_gpu_device = undefined,
    frame: *abi_render_frame.c.ke_render_frame = undefined,
    view_space: *abi_view.c.ke_view_space = undefined,
    camera: *abi_render.c.ke_render_camera = undefined,

    grid_x: u32 = undefined,
    grid_y: u32 = undefined,
    grid_z: u32 = undefined,
    num_clusters: u32 = undefined,
    max_lights_per_cluster: u32 = undefined,

    cluster_grid_uniform: abi_render.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,

    point_lights_sb: abi_render.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    spot_lights_sb: abi_render.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    point_indices_sb: abi_render.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    point_counts_sb: abi_render.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    spot_indices_sb: abi_render.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    spot_counts_sb: abi_render.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    published: [cluster_buffers.len]Published = undefined,
    resources: [cluster_buffers.len]rg.ke_render_graph_resource = [_]rg.ke_render_graph_resource{0} ** cluster_buffers.len,

    cull_pipeline: abi_render.c.ke_gpu_pipeline = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    cull_uniform: abi_render.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    binder: *abi_render_gpu.c.ke_render_resource_binder = undefined,
    cull_layout: abi_render.c.ke_render_shader_layout = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    cull_set: abi_render.c.ke_render_resource_set = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    access: [1]abi_ecs.c.ke_ecs_query_term = undefined,
    cull_queries_terms: [6]abi_ecs.c.ke_ecs_query_term = undefined,
    cull_queries: [3]abi_ecs.c.ke_ecs_query_desc = undefined,

    point_overflow_warned: bool = false,
    spot_overflow_warned: bool = false,
};

const log = std.log.scoped(.render_cluster);

/// Logs that a kind of light overflowed the storage, so only the first `cap` of `total` are used.
fn logLightOverflow(kind: []const u8, total: usize, cap: usize) void {
    log.warn("{s} light count ({d}) exceeds the storage capacity ({d}); only the first {d} are culled/shaded this run", .{ kind, total, cap, cap });
}

inline fn moduleOf(user: ?*anyopaque) *ClusterModule {
    return @alignCast(@ptrCast(user.?));
}

/// "render.cluster.buffers", in the render prepare set: imports every buffer of the result into
/// the frame being declared and publishes it under its name. A frame not being declared gets none;
/// the graph or the frame refusing one fails with its code.
fn prepareSystem(_: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const cm = moduleOf(user);
    const frame = cm.frame;
    if (!frame.live.?(frame)) return R.ok;
    const graph = frame.graph.?(frame).?;
    inline for (cluster_buffers, 0..) |entry, i| {
        const imported = graph.import_buffer.?(graph, cm.published[i].buffer, cm.published[i].size, &cm.resources[i]);
        if (imported != R.ok) return imported;
        const named = frame.publish.?(frame, entry.name, cm.resources[i]);
        if (named != R.ok) return named;
    }
    return R.ok;
}

/// Records the cull: one dispatch per 64 clusters.
fn record(user: ?*anyopaque, ctx: ?*rg.ke_render_graph_ctx) callconv(.c) abi_result.c.ke_result {
    const cm = moduleOf(user);
    const cp: [*c]abi_render_gpu.c.ke_gpu_compute_pass = @ptrCast(ctx.?.compute_pass.?(ctx));
    cp.*.set_pipeline.?(cp, cm.cull_pipeline);
    cm.binder.bind_compute_set.?(cm.binder, cp, cm.cull_set, null, 0);
    cp.*.dispatch.?(cp, (cm.num_clusters + 63) / 64, 1, 1);
    return R.ok;
}

/// "render.cull", in the render queue set. It uploads the light records, staged in a chunk uploaded
/// each time it fills and once more at the end; the records are capped while the totals keep
/// counting, and an overflow is reported once per kind through `logLightOverflow`. A frame not being
/// declared, or one without a camera, stops there; otherwise it uploads the cull parameters and the
/// grid and declares at KE_RENDER_STAGE_PREPASS the compute pass binning the lights. The graph
/// refusing the pass fails with its code.
fn queueSystem(ctx: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const cm = moduleOf(user);
    const core = cm.core;
    const frame = cm.frame;
    if (!frame.live.?(frame)) return R.ok;
    const deg2rad: f32 = std.math.pi / 180.0;
    var pn: u32 = 0;
    var point_total: usize = 0;
    {
        var chunk: [UPLOAD_CHUNK]PointLightGpu = undefined;
        var fill: u32 = 0;
        var segc: usize = 0;
        const segs = ctx.?.view.?(ctx, 0, &segc);
        var s: usize = 0;
        while (s < segc) : (s += 1) {
            const pls: [*c]const abi_render_components.c.ke_point_light_component = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
            const wts: [*c]const abi_spatial.c.ke_world_transform_component = @ptrCast(@alignCast(segs.?[s].columns.?[1]));
            point_total += segs.?[s].count;
            var i: usize = 0;
            while (i < segs.?[s].count and pn < MAX_LIGHTS) : (i += 1) {
                const m = wts[i].matrix.m;
                chunk[fill] = PointLightGpu{
                    .pos_radius = .{ m[12], m[13], m[14], pls[i].radius },
                    .color_intensity = .{ pls[i].color.x, pls[i].color.y, pls[i].color.z, pls[i].intensity },
                };
                fill += 1;
                pn += 1;
                if (fill == UPLOAD_CHUNK) {
                    core.*.upload.?(core, cm.point_lights_sb, (pn - fill) * @sizeOf(PointLightGpu), &chunk, fill * @sizeOf(PointLightGpu));
                    fill = 0;
                }
            }
        }
        if (fill > 0) core.*.upload.?(core, cm.point_lights_sb, (pn - fill) * @sizeOf(PointLightGpu), &chunk, fill * @sizeOf(PointLightGpu));
    }
    if (point_total > MAX_LIGHTS and !cm.point_overflow_warned) {
        logLightOverflow("point", point_total, MAX_LIGHTS);
        cm.point_overflow_warned = true;
    }

    var sn: u32 = 0;
    var spot_total: usize = 0;
    {
        var chunk: [UPLOAD_CHUNK]SpotLightGpu = undefined;
        var fill: u32 = 0;
        var segc: usize = 0;
        const segs = ctx.?.view.?(ctx, 1, &segc);
        var s: usize = 0;
        while (s < segc) : (s += 1) {
            const sls: [*c]const SpotLightComp = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
            const wts: [*c]const abi_spatial.c.ke_world_transform_component = @ptrCast(@alignCast(segs.?[s].columns.?[1]));
            spot_total += segs.?[s].count;
            var i: usize = 0;
            while (i < segs.?[s].count and sn < MAX_LIGHTS) : (i += 1) {
                const m = wts[i].matrix.m;
                chunk[fill] = SpotLightGpu{
                    .pos_range = .{ m[12], m[13], m[14], sls[i].range },
                    .dir_cos_inner = .{ sls[i].dir[0], sls[i].dir[1], sls[i].dir[2], std.math.cos(sls[i].inner_deg * deg2rad) },
                    .color_intensity = .{ sls[i].color[0], sls[i].color[1], sls[i].color[2], sls[i].intensity },
                    .cone = .{ std.math.cos(sls[i].outer_deg * deg2rad), 0.0, 0.0, 0.0 },
                };
                fill += 1;
                sn += 1;
                if (fill == UPLOAD_CHUNK) {
                    core.*.upload.?(core, cm.spot_lights_sb, (sn - fill) * @sizeOf(SpotLightGpu), &chunk, fill * @sizeOf(SpotLightGpu));
                    fill = 0;
                }
            }
        }
        if (fill > 0) core.*.upload.?(core, cm.spot_lights_sb, (sn - fill) * @sizeOf(SpotLightGpu), &chunk, fill * @sizeOf(SpotLightGpu));
    }
    if (spot_total > MAX_LIGHTS and !cm.spot_overflow_warned) {
        logLightOverflow("spot", spot_total, MAX_LIGHTS);
        cm.spot_overflow_warned = true;
    }

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, 2, &cam_segc);
    if (cam_segc == 0 or cam_segs.?[0].count == 0) return R.ok;
    const cam: *const abi_render_components.c.ke_camera_component = @ptrCast(@alignCast(cam_segs.?[0].columns.?[0]));

    var bw: u32 = 0;
    var bh: u32 = 0;
    core.*.backbuffer_size.?(core, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    const depth_from_view_z = cm.view_space.depth_from_view_z.?(cm.view_space);
    var frustum: abi_render.c.ke_camera_frustum = undefined;
    cm.camera.perspective_frustum.?(cm.camera, cam, aspect, &frustum);
    var params: ClusterParams = .{
        .grid = .{ @floatFromInt(cm.grid_x), @floatFromInt(cm.grid_y), @floatFromInt(cm.grid_z), @floatFromInt(cm.max_lights_per_cluster) },
        .counts = .{ @floatFromInt(pn), @floatFromInt(sn), depth_from_view_z, 0.0 },
        .depth = .{ frustum.near_plane, frustum.far_plane, 0.0, 0.0 },
    };
    core.*.upload.?(core, cm.cull_uniform, 0, &params, @sizeOf(ClusterParams));
    uploadGrid(cm, bw, bh, cam.near_plane, cam.far_plane);

    var uses = std.mem.zeroes([written.len]rg.ke_render_graph_use);
    for (written, 0..) |index, i| {
        uses[i].resource = cm.resources[index];
        uses[i].usage = rg.KE_RENDER_GRAPH_USAGE_STORAGE_WRITE;
    }
    var desc = std.mem.zeroes(rg.ke_render_graph_pass_desc);
    desc.name = "render.cull";
    desc.type = rg.KE_RENDER_GRAPH_PASS_COMPUTE;
    desc.injection_point = abi_render.c.KE_RENDER_STAGE_PREPASS;
    desc.uses = &uses;
    desc.use_count = uses.len;
    desc.record = record;
    desc.user = cm;
    const graph = frame.graph.?(frame).?;
    var pass: rg.ke_render_graph_pass = 0;
    return graph.add_pass.?(graph, &desc, &pass);
}

/// Writes the grid uniform that the shading passes read as "cluster_grid": the grid
/// dimensions, the viewport and depth range, and the view space depth conversion.
fn uploadGrid(cm: *const ClusterModule, bw: u32, bh: u32, near: f32, far: f32) void {
    const core = cm.core;
    const grid_data = ClusterGridUniform{
        .cluster_grid = .{ @floatFromInt(cm.grid_x), @floatFromInt(cm.grid_y), @floatFromInt(cm.grid_z), @floatFromInt(cm.max_lights_per_cluster) },
        .cluster_viewport = .{ @floatFromInt(bw), @floatFromInt(bh), near, far },
        .view_space = .{ cm.view_space.depth_from_view_z.?(cm.view_space), 0.0, 0.0, 0.0 },
    };
    core.*.upload.?(core, cm.cluster_grid_uniform, 0, &grid_data, @sizeOf(ClusterGridUniform));
}

fn makeStorageBuffer(dev: *abi_render_gpu.c.ke_gpu_device, label: [*c]const u8, size: usize, out: *abi_render.c.ke_gpu_buffer) R.Error!void {
    try R.check(dev.create_buffer.?(dev, &abi_render_gpu.c.ke_gpu_buffer_desc{
        .label = label,
        .initial_data = null,
        .size = size,
        .usage = abi_render_gpu.c.KE_GPU_BUFFER_USAGE_STORAGE | abi_render_gpu.c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, out));
}

/// Runs once, from `ke_render_cluster_create`. It creates the GPU objects in a fixed order, keeps
/// the buffers it publishes each frame in `published`, and fills the access list and the queries
/// over the render world. A failed step fails with its code, and the objects created before it stay
/// set for `destroyModule` to release.
fn setup(cm: *ClusterModule, service: *abi_render.c.ke_render_service, device: *abi_render_gpu.c.ke_gpu_device, frame: *abi_render_frame.c.ke_render_frame, scene: *abi_render.c.ke_render_scene_resolve, camera: *abi_render.c.ke_render_camera, view_space: *abi_view.c.ke_view_space, config: *const Config) R.Error!void {
    const core: *abi_render.c.ke_render_service = service;
    const dev: *abi_render_gpu.c.ke_gpu_device = device;
    const ids = scene.render_component_ids.?(scene).?;
    cm.core = core;
    cm.device = dev;
    cm.frame = frame;
    cm.view_space = view_space;
    cm.camera = camera;
    cm.grid_x = config.grid_x;
    cm.grid_y = config.grid_y;
    cm.grid_z = config.grid_z;
    cm.max_lights_per_cluster = config.max_lights_per_cluster;
    cm.num_clusters = cm.grid_x * cm.grid_y * cm.grid_z;

    const point_lights_bytes = MAX_LIGHTS * @sizeOf(PointLightGpu);
    const spot_lights_bytes = MAX_LIGHTS * @sizeOf(SpotLightGpu);
    const indices_bytes: usize = @as(usize, cm.num_clusters) * cm.max_lights_per_cluster * @sizeOf(u32);
    const counts_bytes: usize = @as(usize, cm.num_clusters) * @sizeOf(u32);

    try makeStorageBuffer(dev, "cluster.point_lights_sb", point_lights_bytes, &cm.point_lights_sb);
    try makeStorageBuffer(dev, "cluster.spot_lights_sb", spot_lights_bytes, &cm.spot_lights_sb);
    try makeStorageBuffer(dev, "cluster.point_indices_sb", indices_bytes, &cm.point_indices_sb);
    try makeStorageBuffer(dev, "cluster.point_counts_sb", counts_bytes, &cm.point_counts_sb);
    try makeStorageBuffer(dev, "cluster.spot_indices_sb", indices_bytes, &cm.spot_indices_sb);
    try makeStorageBuffer(dev, "cluster.spot_counts_sb", counts_bytes, &cm.spot_counts_sb);

    try R.check(dev.create_buffer.?(dev, &abi_render_gpu.c.ke_gpu_buffer_desc{
        .label = "cluster.cluster_grid_uniform",
        .initial_data = null,
        .size = @sizeOf(ClusterGridUniform),
        .usage = abi_render_gpu.c.KE_GPU_BUFFER_USAGE_UNIFORM | abi_render_gpu.c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, &cm.cluster_grid_uniform));
    cm.published = [_]Published {
        .{ .buffer = cm.point_lights_sb, .size = point_lights_bytes },
        .{ .buffer = cm.spot_lights_sb, .size = spot_lights_bytes },
        .{ .buffer = cm.point_indices_sb, .size = indices_bytes },
        .{ .buffer = cm.point_counts_sb, .size = counts_bytes },
        .{ .buffer = cm.spot_indices_sb, .size = indices_bytes },
        .{ .buffer = cm.spot_counts_sb, .size = counts_bytes },
        .{ .buffer = cm.cluster_grid_uniform, .size = @sizeOf(ClusterGridUniform) },
    };
    cm.binder = core.*.resource_binder.?(core).?;
    try R.check(cm.binder.create_shader_layout.?(cm.binder, &cull_layout_params, &cm.cull_layout));

    try R.check(dev.create_buffer.?(dev, &abi_render_gpu.c.ke_gpu_buffer_desc{
        .label = "cluster.cull_uniform",
        .initial_data = null,
        .size = @sizeOf(ClusterParams),
        .usage = abi_render_gpu.c.KE_GPU_BUFFER_USAGE_UNIFORM | abi_render_gpu.c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, &cm.cull_uniform));
    const cull_bindings = [_]abi_render_gpu.c.ke_render_shader_binding{
        .{ .name = "params", .buffer = cm.cull_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(ClusterParams), .texture_view = 0, .sampler = 0 },
        .{ .name = "point_lights", .buffer = cm.point_lights_sb, .buffer_offset = 0, .buffer_size = point_lights_bytes, .texture_view = 0, .sampler = 0 },
        .{ .name = "spot_lights", .buffer = cm.spot_lights_sb, .buffer_offset = 0, .buffer_size = spot_lights_bytes, .texture_view = 0, .sampler = 0 },
        .{ .name = "point_indices", .buffer = cm.point_indices_sb, .buffer_offset = 0, .buffer_size = indices_bytes, .texture_view = 0, .sampler = 0 },
        .{ .name = "point_counts", .buffer = cm.point_counts_sb, .buffer_offset = 0, .buffer_size = counts_bytes, .texture_view = 0, .sampler = 0 },
        .{ .name = "spot_indices", .buffer = cm.spot_indices_sb, .buffer_offset = 0, .buffer_size = indices_bytes, .texture_view = 0, .sampler = 0 },
        .{ .name = "spot_counts", .buffer = cm.spot_counts_sb, .buffer_offset = 0, .buffer_size = counts_bytes, .texture_view = 0, .sampler = 0 },
    };
    try R.check(cm.binder.create_set.?(cm.binder, cm.cull_layout, null, "cluster.cull_set", &cull_bindings, cull_bindings.len, &cm.cull_set));

    var cs: abi_render.c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "cluster_cull", abi_render_gpu.c.KE_GPU_SHADER_STAGE_COMPUTE, &cs));

    var cull_pipeline_params = abi_render_gpu.c.ke_gpu_compute_pipeline_desc{
        .label = "cluster.cull_pipeline",
        .compute_module = cs,
        .compute_entry = "cs_main",
        .bind_group_layouts = .{ 0, 0, 0, 0 },
        .bind_group_layout_count = 0,
    };
    try R.check(cm.binder.pipeline_layouts.?(cm.binder, cm.cull_layout, &cull_pipeline_params.bind_group_layouts, cull_pipeline_params.bind_group_layouts.len, &cull_pipeline_params.bind_group_layout_count));
    try R.check(dev.create_compute_pipeline.?(dev, &cull_pipeline_params, &cm.cull_pipeline));

    cm.access = .{.{ .component = cm.frame.frame_cid.?(cm.frame), .access = abi_ecs.c.KE_ECS_ACCESS_WRITE }};
    const rd = abi_ecs.c.KE_ECS_ACCESS_READ;
    cm.cull_queries_terms = .{ .{ .component = ids.*.point_light, .access = rd }, .{ .component = ids.*.world_transform, .access = rd }, .{ .component = ids.*.spot_light, .access = rd }, .{ .component = ids.*.world_transform, .access = rd }, .{ .component = ids.*.camera, .access = rd }, .{ .component = ids.*.world_transform, .access = rd } };
    cm.cull_queries = .{ .{ .terms = cm.cull_queries_terms[0..].ptr, .term_count = 2 }, .{ .terms = cm.cull_queries_terms[2..].ptr, .term_count = 2 }, .{ .terms = cm.cull_queries_terms[4..].ptr, .term_count = 2 } };
}

/// Releases every GPU object, set and layout whose handle is not the invalid one, so it is safe on a module that
/// `setup` did not finish. The device and the borrowed pointers are not released.
fn destroyModule(cm: *const ClusterModule) void {
    const dev = cm.device;
    const invalid = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    if (cm.cull_pipeline != invalid) dev.destroy_compute_pipeline.?(dev, cm.cull_pipeline);
    if (cm.cull_layout != abi_render_gpu.c.KE_RENDER_BINDING_INVALID) {
        cm.binder.destroy_set.?(cm.binder, cm.cull_set);
        cm.binder.destroy_shader_layout.?(cm.binder, cm.cull_layout);
    }
    if (cm.cull_uniform != invalid) dev.destroy_buffer.?(dev, cm.cull_uniform);
    if (cm.cluster_grid_uniform != invalid) dev.destroy_buffer.?(dev, cm.cluster_grid_uniform);
    const storage = [_]abi_render.c.ke_gpu_buffer{
        cm.point_lights_sb,  cm.spot_lights_sb,
        cm.point_indices_sb, cm.point_counts_sb,
        cm.spot_indices_sb,  cm.spot_counts_sb,
    };
    for (storage) |buffer| {
        if (buffer != invalid) dev.destroy_buffer.?(dev, buffer);
    }
}

/// The `destroy` of the owner `ke_render_cluster_create` hands out: unregisters the systems, releases the GPU
/// objects and frees the pass; a null argument is ignored.
fn destroyOwner(ref: ?*anyopaque) callconv(.c) void {
    const cm: *ClusterModule = @ptrCast(@alignCast(ref orelse return));
    cm.systems.unregister();
    destroyModule(cm);
    gpa.destroy(cm);
}

/// The factory declared in cluster_create.h. A missing part of the context or settings, or a setting
/// the schema refuses, fails as an invalid argument and a module that cannot be allocated as out of
/// memory. The handle stays zeroed when `setup` fails, and the objects created so far are released
/// then.
export fn ke_render_cluster_create(
    service_in: ?*abi_render.c.ke_render_service,
    device_in: ?*abi_render_gpu.c.ke_gpu_device,
    frame_in: ?*abi_render_frame.c.ke_render_frame,
    scene_in: ?*abi_render.c.ke_render_scene_resolve,
    camera_in: ?*abi_render.c.ke_render_camera,
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
    const camera = camera_in orelse return R.code(error.InvalidArgument);
    const view_space = view_space_in orelse return R.code(error.InvalidArgument);
    if (render_prepare == null) return R.code(error.InvalidArgument);
    if (render_queue == null) return R.code(error.InvalidArgument);
    const values = settings_schema.read(Config, settings orelse {
        log.warn("cluster pass: no settings", .{});
        return R.code(error.InvalidArgument);
    }) catch |err| return R.code(err);
    const given = &values;
    const cm = gpa.create(ClusterModule) catch |err| return R.code(err);
    cm.* = .{};
    setup(cm, service, device, frame, scene, camera, view_space, given) catch |err| {
        destroyModule(cm);
        gpa.destroy(cm);
        return R.code(err);
    };
    const registered = cm.systems.register(.{
        .{ .name = "render.cluster.buffers", .execute = prepareSystem, .user = cm, .hook = 0, .access = &cm.access },
        .{ .name = "render.cull", .execute = queueSystem, .user = cm, .hook = 1, .queries = &cm.cull_queries, .access = &cm.access },
    }, &.{ .{ .schedule = render_prepare, .set = render_prepare_set }, .{ .schedule = render_queue, .set = render_queue_set } });
    if (registered != R.ok) {
        destroyModule(cm);
        gpa.destroy(cm);
        return registered;
    }
    out.* = .{ .ref = cm, .destroy = destroyOwner };
    return R.ok;
}

pub const parts = [_]abi_part.c.ke_part{
    part.of(ke_render_cluster_create, .{ .name = "render_cluster", .slots = &.{"service", "device", "frame", "scene", "camera", "view_space"}, .hooks = &.{"render_prepare", "render_queue"}, .set_log = @ptrCast(&@import("log").Destination("ke_render_cluster").setLogCallback) }),
};

/// The library's parts.
export fn ke_render_cluster_parts(out_count: ?*usize) callconv(.c) ?*const abi_part.c.ke_part {
    if (out_count) |n| n.* = parts.len;
    return &parts[0];
}

const testing = std.testing;
const zsub = @import("zsub");

const test_ids = std.mem.zeroInit(abi_render.c.ke_render_scene_component_ids, .{ .mesh = 1, .camera = 2, .directional_light = 3, .point_light = 4, .spot_light = 5, .ambient_light = 6, .skybox = 7, .sprite2d = 8, .label = 9, .world_transform = 10 });

fn testComponentIds(_: ?*abi_render.c.ke_render_scene_resolve) callconv(.c) ?*const abi_render.c.ke_render_scene_component_ids {
    return &test_ids;
}

var test_scene: abi_render.c.ke_render_scene_resolve = .{ .handle = null, .component_ids = testComponentIds, .render_component_ids = testComponentIds };

var test_camera_component = std.mem.zeroes(abi_render_components.c.ke_camera_component);
var camera_columns = [_]?*anyopaque{ @ptrCast(&test_camera_component), @ptrCast(&test_camera_component) };
var camera_segment: abi_ecs.c.ke_ecs_segment = .{ .entities = null, .count = 1, .columns = &camera_columns, .column_count = 2 };

fn cameraView(_: ?*abi_schedule.c.ke_schedule_ctx, index: u32, out_count: ?*usize) callconv(.c) ?[*]const abi_ecs.c.ke_ecs_segment {
    out_count.?.* = if (index == 2) 1 else 0;
    return if (index == 2) (&camera_segment)[0..1] else null;
}

var camera_ctx: abi_schedule.c.ke_schedule_ctx = .{ .handle = null, .commands = null, .view = cameraView, .slice = null };
var empty_ctx: abi_schedule.c.ke_schedule_ctx = std.mem.zeroes(abi_schedule.c.ke_schedule_ctx);

fn viewDepthFromViewZ(_: ?*abi_view.c.ke_view_space) callconv(.c) f32 {
    return 0.0;
}

/// The parts a pass is made of in a test.
const Rig = struct {
    dev: zsub.For(abi_render_gpu.c.ke_gpu_device),
    binder: zsub.For(abi_render_gpu.c.ke_render_resource_binder),
    core: zsub.For(abi_render.c.ke_render_service),
    schedule: zsub.For(abi_schedule.c.ke_schedule),
    frame: zsub.For(abi_render_frame.c.ke_render_frame),
    graph: zsub.For(rg.ke_render_graph),
    camera: zsub.For(abi_render.c.ke_render_camera),
    view_space: abi_view.c.ke_view_space,

    fn init(self: *Rig) !void {
        try self.dev.init();
        _ = self.dev.when(.create_buffer).writesFresh(2);
        _ = self.dev.when(.create_compute_pipeline).writesFresh(2);
        try self.binder.init();
        _ = self.binder.when(.create_shader_layout).writesFresh(2);
        _ = self.binder.when(.create_set).writesFresh(6);
        try self.core.init();
        _ = self.core.when(.resource_binder).returns(self.binder.api());
        _ = self.core.when(.load_shader).writesFresh(3);
        try self.schedule.init();
        _ = self.schedule.when(.register_system).writesFresh(2);
        try self.graph.init();
        _ = self.graph.when(.import_buffer).writesFresh(3);
        try self.camera.init();
        self.view_space = std.mem.zeroes(abi_view.c.ke_view_space);
        self.view_space.depth_from_view_z = viewDepthFromViewZ;
        try self.frame.init();
        _ = self.frame.when(.frame_cid).returns(11);
        _ = self.frame.when(.live).returns(true);
        _ = self.frame.when(.graph).returns(self.graph.api());
    }

    fn deinit(self: *Rig) void {
        self.frame.deinit();
        self.camera.deinit();
        self.graph.deinit();
        self.schedule.deinit();
        self.core.deinit();
        self.binder.deinit();
        self.dev.deinit();
    }

    fn create(self: *Rig, settings: ?*abi_settings.c.ke_settings, out: *abi_part.c.ke_owner) abi_result.c.ke_result {
        return ke_render_cluster_create(self.core.api(), self.dev.api(), self.frame.api(), &test_scene, self.camera.api(), &self.view_space, self.schedule.api(), 4, self.schedule.api(), 5, settings, out);
    }

    fn expectReleased(self: *Rig) !void {
        try self.dev.received(.destroy_buffer).where(zsub.argIsNot(1, abi_render_gpu.c.KE_GPU_INVALID_HANDLE)).sameAs(self.dev.received(.create_buffer));
        try self.dev.received(.destroy_compute_pipeline).where(zsub.argIsNot(1, abi_render_gpu.c.KE_GPU_INVALID_HANDLE)).sameAs(self.dev.received(.create_compute_pipeline));
        try self.binder.received(.destroy_shader_layout).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_shader_layout));
        try self.binder.received(.destroy_set).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_set));
    }
};

var test_settings = settings_schema.Fixed.init(&.{ .{ .key = "grid_x", .value = .{ .int = 4 } }, .{ .key = "grid_y", .value = .{ .int = 4 } }, .{ .key = "grid_z", .value = .{ .int = 4 } }, .{ .key = "max_lights_per_cluster", .value = .{ .int = 8 } } });

fn passOf(h: abi_part.c.ke_owner) *ClusterModule {
    return @ptrCast(@alignCast(h.ref.?));
}

test "the cluster pass registers its two systems in its hooks, and destroying it unregisters them and releases the GPU objects" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_part.c.ke_owner = undefined;
    try R.check(rig.create(&test_settings.api, &h));
    try rig.schedule.received(.register_system).times(2);
    h.destroy.?(h.ref);
    try rig.schedule.received(.unregister_system).times(2);
    try rig.expectReleased();
}

test "the cluster publishes every buffer of its result, and declares the cull at the prepass stage when a camera sees" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_part.c.ke_owner = undefined;
    try R.check(rig.create(&test_settings.api, &h));
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, prepareSystem(&empty_ctx, passOf(h), 0));
    try rig.frame.received(.publish).times(cluster_buffers.len);
    try testing.expectEqual(R.ok, queueSystem(&camera_ctx, passOf(h), 0));
    try rig.graph.received(.add_pass).times(1);
}

test "a cluster setting of zero is refused and releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
        var bad = settings_schema.Fixed.init(&.{.{ .key = "grid_z", .value = .{ .int = 0 } }});
    var h: abi_part.c.ke_owner = undefined;
    try testing.expectError(error.InvalidArgument, R.check(rig.create(&bad.api, &h)));
    try testing.expect(h.ref == null);
    try rig.expectReleased();
}

test "a cluster pass missing its camera is refused as an invalid argument" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_part.c.ke_owner = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_cluster_create(rig.core.api(), rig.dev.api(), rig.frame.api(), &test_scene, null, &rig.view_space, rig.schedule.api(), 4, rig.schedule.api(), 5, &test_settings.api, &h)));
}

test "creating and destroying cluster passes leaves no block allocated" {
    try heap.expectNoLeaks();
}

test "the library's parts name render_cluster and their slots" {
    var count: usize = 0;
    const all = ke_render_cluster_parts(&count).?;
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqualStrings("render_cluster", std.mem.span(@as([*]const abi_part.c.ke_part, @ptrCast(all))[0].name.?));
    try std.testing.expectEqual(@as(usize, 8), @as([*]const abi_part.c.ke_part, @ptrCast(all))[0].slot_count);
}
