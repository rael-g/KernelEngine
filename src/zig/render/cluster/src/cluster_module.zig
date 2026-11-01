//! The cluster pass: the render-phase system "render.cull" that gathers the point and spot lights
//! of a frame into GPU buffers and bins them into a view-space grid of clusters. It publishes each
//! buffer of the result to the render service under its own name.

const abi_framework = @import("abi_framework");
const abi_render_contract = @import("abi_render_contract");
const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_components = @import("abi_render_components");
const abi_render_gpu = @import("abi_render_gpu");
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_cluster").logFn };

const feature_bindings = @import("feature_bindings");
const cluster_buffers = feature_bindings.cluster_buffers;
const c = @import("c");
const abi_ecs = @import("abi_ecs");
const abi_render = @import("abi_render");
const abi_configuration = @import("abi_configuration");
const abi_render_cluster_factory = @import("abi_render_cluster_factory");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const abi_spatial = @import("abi_spatial");
const abi_view = @import("abi_view");
const R = @import("result").Result(.{});

const heap = @import("heap");
const gpa = heap.gpa;

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

const cull_layout_params = abi_render_gpu.c.ke_render_shader_layout_params{
    .shader = "cluster_cull",
    .stages = abi_render_gpu.c.KE_GPU_SHADER_STAGE_COMPUTE,
    .hints = null,
    .hint_count = 0,
};

/// State of one cluster pass, allocated by `ke_render_cluster_create` and freed by `destroyHandle`.
/// The core, device, view space and camera are borrowed: the module stores them and never
/// releases them. The component ids, grid fields and access data are assigned by `setup`, so they
/// are undefined until it runs; the GPU fields are the invalid handle until their own creation
/// succeeds.
/// `destroyHandle` unregisters the system the factory registered before it frees the module.
const ClusterModule = struct {
    runtime: *abi_runtime.c.ke_runtime = undefined,
    system: abi_framework.c.ke_system_id = 0,
    core: *abi_render.c.ke_render_service = undefined,
    device: *abi_render_gpu.c.ke_gpu_device = undefined,
    view_space: *abi_view.c.ke_view_space = undefined,
    camera: *abi_render.c.ke_render_camera = undefined,
    point_light_cid: abi_asset_resolver.c.ke_component_id = undefined,
    spot_light_cid: abi_asset_resolver.c.ke_component_id = undefined,
    world_transform_cid: abi_asset_resolver.c.ke_component_id = undefined,
    camera_cid: abi_asset_resolver.c.ke_component_id = undefined,
    frame_cid: abi_asset_resolver.c.ke_component_id = undefined,

    grid_x: u32 = undefined,
    grid_y: u32 = undefined,
    grid_z: u32 = undefined,
    num_clusters: u32 = undefined,
    max_lights_per_cluster: u32 = undefined,

    cluster_grid_uniform: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,

    point_lights_sb: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    spot_lights_sb: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    point_indices_sb: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    point_counts_sb: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    spot_indices_sb: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    spot_counts_sb: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,

    cull_pipeline: abi_asset_resolver.c.ke_gpu_pipeline = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    cull_uniform: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    binder: *abi_render_gpu.c.ke_render_resource_binder = undefined,
    cull_layout: abi_asset_resolver.c.ke_render_shader_layout = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    cull_set: abi_asset_resolver.c.ke_render_resource_set = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    cull_io: abi_render.c.ke_render_pass_io = undefined,
    cull_access: [6]abi_runtime.c.ke_component_access = undefined,
    cull_queries_terms: [6]abi_runtime.c.ke_component_access = undefined,
    cull_queries: [3]abi_runtime.c.ke_query_decl = undefined,
    clusters_cid: abi_asset_resolver.c.ke_component_id = undefined,

    point_overflow_warned: bool = false,
    spot_overflow_warned: bool = false,
};

const log = std.log.scoped(.render_cluster);

/// Logs that a kind of light overflowed the storage, so only the first `cap` of `total` are used.
fn logLightOverflow(kind: []const u8, total: usize, cap: usize) void {
    log.warn("{s} light count ({d}) exceeds the storage capacity ({d}); only the first {d} are culled/shaded this run", .{ kind, total, cap, cap });
}

/// Recovers the module that `ke_render_cluster_create` passed as the system's user data.
inline fn moduleOf(user: ?*anyopaque) *ClusterModule {
    return @alignCast(@ptrCast(user.?));
}

/// The per-frame body that `ke_render_cluster_create` registers. It succeeds on every path. Light records are staged in a chunk that is uploaded each time
/// it fills and once more at the end; the records are capped while the totals keep counting, and an
/// overflow is reported once per kind through `logLightOverflow`. A frame without a camera uploads
/// the lights and stops; otherwise it also uploads the cull parameters and the grid and dispatches
/// the compute pipeline.
fn system(ctx: ?*abi_runtime.c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const cm = moduleOf(user);
    const core = cm.core;
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

    const pc = core.*.begin_pass.?(core, &cm.cull_io);
    if (pc == null) return R.ok;

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.?.backbuffer_size.?(pc, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    const depth_from_view_z = cm.view_space.params.?(cm.view_space).depth_from_view_z;
    var frustum: abi_render.c.ke_camera_frustum = undefined;
    cm.camera.perspective_frustum.?(cm.camera, cam, aspect, &frustum);
    var params: ClusterParams = .{
        .grid = .{ @floatFromInt(cm.grid_x), @floatFromInt(cm.grid_y), @floatFromInt(cm.grid_z), @floatFromInt(cm.max_lights_per_cluster) },
        .counts = .{ @floatFromInt(pn), @floatFromInt(sn), depth_from_view_z, 0.0 },
        .depth = .{ frustum.near_plane, frustum.far_plane, 0.0, 0.0 },
    };
    core.*.upload.?(core, cm.cull_uniform, 0, &params, @sizeOf(ClusterParams));

    uploadGrid(cm, bw, bh, cam.near_plane, cam.far_plane);

    const cp = pc.?.begin_compute.?(pc);
    cp.?.set_pipeline.?(cp, cm.cull_pipeline);
    cm.binder.bind_compute_set.?(cm.binder, cp, cm.cull_set, null, 0);
    cp.?.dispatch.?(cp, (cm.num_clusters + 63) / 64, 1, 1);
    cp.?.end.?(cp);
    core.*.end_pass.?(core, pc);
    return R.ok;
}

/// Writes the grid uniform that the shading passes read as "cluster_grid": the grid
/// dimensions, the viewport and depth range, and the view space depth conversion.
fn uploadGrid(cm: *const ClusterModule, bw: u32, bh: u32, near: f32, far: f32) void {
    const core = cm.core;
    const grid_data = ClusterGridUniform{
        .cluster_grid = .{ @floatFromInt(cm.grid_x), @floatFromInt(cm.grid_y), @floatFromInt(cm.grid_z), @floatFromInt(cm.max_lights_per_cluster) },
        .cluster_viewport = .{ @floatFromInt(bw), @floatFromInt(bh), near, far },
        .view_space = .{ cm.view_space.params.?(cm.view_space).depth_from_view_z, 0.0, 0.0, 0.0 },
    };
    core.*.upload.?(core, cm.cluster_grid_uniform, 0, &grid_data, @sizeOf(ClusterGridUniform));
}

fn makeStorageBuffer(dev: *abi_render_gpu.c.ke_gpu_device, label: [*c]const u8, size: usize, out: *abi_asset_resolver.c.ke_gpu_buffer) R.Error!void {
    try R.check(dev.create_buffer.?(dev, &abi_render_gpu.c.ke_gpu_buffer_params{
        .label = label,
        .initial_data = null,
        .size = size,
        .usage = abi_render_gpu.c.KE_GPU_BUFFER_USAGE_STORAGE | abi_render_gpu.c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, out));
}

/// Runs once, from `ke_render_cluster_create`, before the module is registered. It creates the GPU
/// objects in a fixed order, publishes the light lists and the grid to the render service under
/// its group's names, and fills the access list, which writes the group's tag, and the queries. A
/// failed step fails with its code, and the objects
/// created before it stay set for `destroyModule` to release.
fn setup(cm: *ClusterModule, p: *const abi_render_cluster_factory.c.ke_render_cluster_params) R.Error!void {
    const core: *abi_render.c.ke_render_service = p.service.?;
    const dev: *abi_render_gpu.c.ke_gpu_device = p.device.?;
    cm.core = core;
    cm.device = dev;
    cm.view_space = p.view_space.?;
    cm.camera = p.camera.?;
    cm.point_light_cid = p.scene.?.component_ids.?(p.scene).?.point_light;
    cm.spot_light_cid = p.scene.?.component_ids.?(p.scene).?.spot_light;
    cm.world_transform_cid = p.scene.?.component_ids.?(p.scene).?.world_transform;
    cm.camera_cid = p.scene.?.component_ids.?(p.scene).?.camera;
    cm.frame_cid = p.frame.?.frame_cid.?(p.frame);
    cm.grid_x = setting(p, p.grid_x, "cluster_grid_x", default_grid_x);
    cm.grid_y = setting(p, p.grid_y, "cluster_grid_y", default_grid_y);
    cm.grid_z = setting(p, p.grid_z, "cluster_grid_z", default_grid_z);
    cm.max_lights_per_cluster = setting(p, p.max_lights_per_cluster, "max_lights_per_cluster", default_max_lights_per_cluster);
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

    try R.check(dev.create_buffer.?(dev, &abi_render_gpu.c.ke_gpu_buffer_params{
        .label = "cluster.cluster_grid_uniform",
        .initial_data = null,
        .size = @sizeOf(ClusterGridUniform),
        .usage = abi_render_gpu.c.KE_GPU_BUFFER_USAGE_UNIFORM | abi_render_gpu.c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, &cm.cluster_grid_uniform));
    const published = [_]struct { buffer: abi_asset_resolver.c.ke_gpu_buffer, size: usize }{
        .{ .buffer = cm.point_lights_sb, .size = point_lights_bytes },
        .{ .buffer = cm.spot_lights_sb, .size = spot_lights_bytes },
        .{ .buffer = cm.point_indices_sb, .size = indices_bytes },
        .{ .buffer = cm.point_counts_sb, .size = counts_bytes },
        .{ .buffer = cm.spot_indices_sb, .size = indices_bytes },
        .{ .buffer = cm.spot_counts_sb, .size = counts_bytes },
        .{ .buffer = cm.cluster_grid_uniform, .size = @sizeOf(ClusterGridUniform) },
    };
    for (cluster_buffers, published) |entry, buffer| {
        var buf: [feature_bindings.name_capacity]u8 = undefined;
        const name = feature_bindings.subName(&buf, p.output.?, entry.suffix) orelse return error.OutOfMemory;
        var cid: abi_asset_resolver.c.ke_component_id = undefined;
        try R.check(core.*.import_buffer.?(core, name, buffer.buffer, buffer.size, &cid));
    }

    cm.binder = core.*.resource_binder.?(core).?;
    try R.check(cm.binder.create_shader_layout.?(cm.binder, &cull_layout_params, &cm.cull_layout));

    try R.check(dev.create_buffer.?(dev, &abi_render_gpu.c.ke_gpu_buffer_params{
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

    var cs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "cluster_cull", abi_render_gpu.c.KE_GPU_SHADER_STAGE_COMPUTE, &cs));

    var cull_pipeline_params = abi_render_gpu.c.ke_gpu_compute_pipeline_params{
        .label = "cluster.cull_pipeline",
        .compute_module = cs,
        .compute_entry = "cs_main",
        .bind_group_layouts = .{ 0, 0, 0, 0 },
        .bind_group_layout_count = 0,
    };
    try R.check(cm.binder.pipeline_layouts.?(cm.binder, cm.cull_layout, &cull_pipeline_params.bind_group_layouts, cull_pipeline_params.bind_group_layouts.len, &cull_pipeline_params.bind_group_layout_count));
    try R.check(dev.create_compute_pipeline.?(dev, &cull_pipeline_params, &cm.cull_pipeline));

    try R.check(core.*.import_tag.?(core, p.output, &cm.clusters_cid));
    cm.cull_io = std.mem.zeroes(abi_render.c.ke_render_pass_io);
    cm.cull_io.name = "render.cull";
    cm.cull_access = .{
        .{ .cid = cm.clusters_cid, .access = abi_runtime.c.KE_ACCESS_WRITE },
        .{ .cid = cm.point_light_cid, .access = abi_runtime.c.KE_ACCESS_READ },
        .{ .cid = cm.spot_light_cid, .access = abi_runtime.c.KE_ACCESS_READ },
        .{ .cid = cm.world_transform_cid, .access = abi_runtime.c.KE_ACCESS_READ },
        .{ .cid = cm.camera_cid, .access = abi_runtime.c.KE_ACCESS_READ },
        .{ .cid = cm.frame_cid, .access = abi_runtime.c.KE_ACCESS_READ },
    };

    const rd = abi_runtime.c.KE_ACCESS_READ;
    cm.cull_queries_terms = .{ .{ .cid = cm.point_light_cid, .access = rd }, .{ .cid = cm.world_transform_cid, .access = rd }, .{ .cid = cm.spot_light_cid, .access = rd }, .{ .cid = cm.world_transform_cid, .access = rd }, .{ .cid = cm.camera_cid, .access = rd }, .{ .cid = cm.world_transform_cid, .access = rd } };
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
    const storage = [_]abi_asset_resolver.c.ke_gpu_buffer{
        cm.point_lights_sb,  cm.spot_lights_sb,
        cm.point_indices_sb, cm.point_counts_sb,
        cm.spot_indices_sb,  cm.spot_counts_sb,
    };
    for (storage) |buffer| {
        if (buffer != invalid) dev.destroy_buffer.?(dev, buffer);
    }
}

/// The `destroy` slot of the handle `ke_render_cluster_create` returns. It releases the GPU objects
/// and frees the module, so the `ref` it was given is invalid afterwards.
fn destroyHandle(self: ?*abi_render_cluster_factory.c.ke_render_cluster) callconv(.c) void {
    const cm: *ClusterModule = @ptrCast(@alignCast(self orelse return));
    _ = cm.runtime.unregister_system.?(cm.runtime, cm.system);
    destroyModule(cm);
    gpa.destroy(cm);
}

/// Builds a cluster pass on the render service and device given, and registers its system with the
/// runtime given. A missing runtime, service, device, view space, camera or output fails as an
/// invalid argument and a module that cannot be allocated as out of memory. The handle's `ref` is
/// null when `setup` fails or the runtime refuses the registration, and the objects created so far
/// are released then.
fn setting(p: *const abi_render_cluster_factory.c.ke_render_cluster_params, given: u32, key: [*c]const u8, default: u32) u32 {
    if (given != 0) return given;
    const store = p.configuration orelse return default;
    const stored = store.*.get_int.?(store, "render", key, 0);
    return if (stored > 0) @intCast(stored) else default;
}

export fn ke_render_cluster_create(params_in: ?*const abi_render_cluster_factory.c.ke_render_cluster_params, out_cluster: [*c]abi_render_cluster_factory.c.ke_render_cluster_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_cluster orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const p = params_in orelse return R.code(error.InvalidArgument);
    const rt: *abi_runtime.c.ke_runtime = p.runtime orelse return R.code(error.InvalidArgument);
    if (p.scene == null or p.frame == null or p.service == null or p.device == null or p.view_space == null or p.camera == null or p.output == null)
        return R.code(error.InvalidArgument);

    const cm = gpa.create(ClusterModule) catch |err| return R.code(err);
    cm.* = .{};
    setup(cm, p) catch |err| {
        destroyModule(cm);
        gpa.destroy(cm);
        return R.code(err);
    };

    var params = std.mem.zeroes(abi_runtime.c.ke_runtime_system_params);
    params.name = "render.cull";
    params.phase = abi_runtime.c.KE_PHASE_RENDER;
    params.queries = &cm.cull_queries;
    params.query_count = cm.cull_queries.len;
    params.access_list = &cm.cull_access;
    params.access_count = cm.cull_access.len;
    params.user_data = cm;
    params.execute = system;
    var system_id: abi_framework.c.ke_system_id = 0;
    const registered = rt.register_system.?(rt, &params, &system_id);
    if (registered != R.ok) {
        destroyModule(cm);
        gpa.destroy(cm);
        return registered;
    }
    cm.runtime = rt;
    cm.system = system_id;

    out.* = .{ .ref = @ptrCast(cm), .destroy = destroyHandle };
    return R.ok;
}

const default_grid_x = 16;
const default_grid_y = 9;
const default_grid_z = 24;
const default_max_lights_per_cluster = 64;



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
        _ = self.dev.when(.create_compute_pipeline).writesFresh(2);
        try self.binder.init();
        _ = self.binder.when(.create_shader_layout).writesFresh(2);
        _ = self.binder.when(.create_set).writesFresh(6);
        try self.core.init();
        _ = self.core.when(.resource_binder).returns(self.binder.api());
        _ = self.core.when(.load_shader).writesFresh(3);
        _ = self.core.when(.cid).returnsFresh();
        _ = self.core.when(.import_buffer).writesFresh(4);
        _ = self.core.when(.import_tag).writesFresh(2);
        _ = self.core.when(.resource_view).returnsFresh();
        _ = self.core.when(.texture_view).returnsFresh();
        _ = self.core.when(.white_texture).returns(.{ .bits = 1 });
        _ = self.core.when(.resource_buffer).returnsFresh();
        _ = self.core.when(.resource_buffer_size).returns(256);
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
        try self.dev.received(.destroy_compute_pipeline).where(zsub.argIsNot(1, abi_render_gpu.c.KE_GPU_INVALID_HANDLE)).sameAs(self.dev.received(.create_compute_pipeline));
        try self.binder.received(.destroy_shader_layout).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_shader_layout));
        try self.binder.received(.destroy_set).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_set));
    }
};

test "creating and destroying the cluster pass leaves no block allocated and no GPU resource live" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var camera = std.mem.zeroes(abi_render.c.ke_render_camera);
    var view_space = std.mem.zeroes(abi_view.c.ke_view_space);
    var h: abi_render_cluster_factory.c.ke_render_cluster_handle = undefined;
    try R.check(ke_render_cluster_create(&.{ .scene = &test_scene, .frame = &test_frame, .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .view_space = &view_space, .camera = &camera, .output = "clusters", .grid_x = 16, .grid_y = 9, .grid_z = 24, .max_lights_per_cluster = 64 }, &h));
    h.destroy.?(h.ref);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}

test "destroying the cluster pass unregisters every system it registered" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var camera = std.mem.zeroes(abi_render.c.ke_render_camera);
    var view_space = std.mem.zeroes(abi_view.c.ke_view_space);
    var h: abi_render_cluster_factory.c.ke_render_cluster_handle = undefined;
    try R.check(ke_render_cluster_create(&.{ .scene = &test_scene, .frame = &test_frame, .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .view_space = &view_space, .camera = &camera, .output = "clusters", .grid_x = 16, .grid_y = 9, .grid_z = 24, .max_lights_per_cluster = 64 }, &h));
    h.destroy.?(h.ref);
    try rig.rt.received(.register_system).atLeast(1);
    try rig.rt.received(.unregister_system).where(zsub.argIs(1, @as(abi_framework.c.ke_system_id, 0))).never();
    try rig.rt.received(.unregister_system).sameAs(rig.rt.received(.register_system));
}

test "a cluster pass whose shader fails to load releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.core.when(.load_shader).returns(abi_result.c.KE_RESULT_GENERAL);
    var camera = std.mem.zeroes(abi_render.c.ke_render_camera);
    var view_space = std.mem.zeroes(abi_view.c.ke_view_space);
    var h: abi_render_cluster_factory.c.ke_render_cluster_handle = undefined;
    try testing.expect(ke_render_cluster_create(&.{ .scene = &test_scene, .frame = &test_frame, .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .view_space = &view_space, .camera = &camera, .output = "clusters", .grid_x = 16, .grid_y = 9, .grid_z = 24, .max_lights_per_cluster = 64 }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}

fn storedGridX(_: [*c]abi_configuration.c.ke_configuration, _: [*c]const u8, _: [*c]const u8, _: i64) callconv(.c) i64 {
    return 7;
}

fn missingKey(_: [*c]abi_configuration.c.ke_configuration, _: [*c]const u8, _: [*c]const u8, fallback: i64) callconv(.c) i64 {
    return fallback;
}

test "a given grid value wins over the store and the store over the default" {
    var store = std.mem.zeroes(abi_configuration.c.ke_configuration);
    store.get_int = storedGridX;
    var p = std.mem.zeroes(abi_render_cluster_factory.c.ke_render_cluster_params);
    try testing.expectEqual(@as(u32, 3), setting(&p, 0, "k", 3));
    p.configuration = @ptrCast(&store);
    try testing.expectEqual(@as(u32, 7), setting(&p, 0, "k", 3));
    try testing.expectEqual(@as(u32, 5), setting(&p, 5, "k", 3));
    store.get_int = missingKey;
    try testing.expectEqual(@as(u32, 3), setting(&p, 0, "k", 3));
}

test "a cluster pass the runtime refuses to register releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.rt.when(.register_system).returns(abi_result.c.KE_RESULT_OUT_OF_MEMORY);
    var camera = std.mem.zeroes(abi_render.c.ke_render_camera);
    var view_space = std.mem.zeroes(abi_view.c.ke_view_space);
    var h: abi_render_cluster_factory.c.ke_render_cluster_handle = undefined;
    try testing.expect(ke_render_cluster_create(&.{ .scene = &test_scene, .frame = &test_frame, .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .view_space = &view_space, .camera = &camera, .output = "clusters", .grid_x = 16, .grid_y = 9, .grid_z = 24, .max_lights_per_cluster = 64 }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}
