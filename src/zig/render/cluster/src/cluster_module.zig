//! The cluster pass: the render-phase system "render.cull" that gathers the point and spot lights
//! of a frame into GPU buffers and bins them into a view-space grid of clusters. It publishes each
//! buffer of the result to the render service under its own name.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };
const feature_bindings = @import("feature_bindings");
const c = @import("c");

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

const cull_layout_params = c.ke_render_shader_layout_params{
    .shader = "cluster_cull",
    .stages = c.KE_GPU_SHADER_STAGE_COMPUTE,
    .hints = null,
    .hint_count = 0,
};

/// State of one cluster pass, allocated by `ke_render_cluster_create` and freed by `destroyHandle`.
/// The core, device, logger, view space and camera are borrowed: the module stores them and never
/// releases them. The component ids, grid fields and access data are assigned by `setup`, so they
/// are undefined until it runs; the GPU fields are the invalid handle until their own creation
/// succeeds.
const ClusterModule = struct {
    core: *c.ke_render_service = undefined,
    device: *c.ke_gpu_device = undefined,
    logger: ?*c.ke_logger = null,
    view_space: *c.ke_view_space = undefined,
    camera: *c.ke_render_camera = undefined,
    point_light_cid: c.ke_component_id = undefined,
    spot_light_cid: c.ke_component_id = undefined,
    world_transform_cid: c.ke_component_id = undefined,
    camera_cid: c.ke_component_id = undefined,
    frame_cid: c.ke_component_id = undefined,

    grid_x: u32 = undefined,
    grid_y: u32 = undefined,
    grid_z: u32 = undefined,
    num_clusters: u32 = undefined,
    max_lights_per_cluster: u32 = undefined,

    cluster_grid_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,

    point_lights_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    spot_lights_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    point_indices_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    point_counts_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    spot_indices_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    spot_counts_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,

    cull_pipeline: c.ke_gpu_pipeline = c.KE_GPU_INVALID_HANDLE,
    cull_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    binder: *c.ke_render_resource_binder = undefined,
    cull_layout: c.ke_render_shader_layout = c.KE_RENDER_BINDING_INVALID,
    cull_set: c.ke_render_resource_set = c.KE_RENDER_BINDING_INVALID,
    cull_io: c.ke_render_pass_io = undefined,
    cull_access: [6]c.ke_component_access = undefined,
    cull_queries_terms: [6]c.ke_component_access = undefined,
    cull_queries: [3]c.ke_query_decl = undefined,
    clusters_cid: c.ke_component_id = undefined,

    point_overflow_warned: bool = false,
    spot_overflow_warned: bool = false,
};

/// Logs the overflow warning through the logger when there is one. The text is formatted into a
/// fixed stack buffer, and a text that does not fit is dropped silently.
fn logLightOverflow(logger: ?*c.ke_logger, kind: []const u8, total: usize, cap: usize) void {
    const lg = logger orelse return;
    var buf: [192]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "{s} light count ({d}) exceeds the storage capacity ({d}); only the first {d} are culled/shaded this run", .{ kind, total, cap, cap }) catch return;
    var ev = c.ke_log_event{ .level = c.KE_LOG_LEVEL_WARNING, .tag = "render_service", .message = msg.ptr };
    lg.log.?(lg, &ev);
}

/// Recovers the module that `ke_render_cluster_create` passed as the system's user data.
inline fn moduleOf(user: ?*anyopaque) *ClusterModule {
    return @alignCast(@ptrCast(user.?));
}

/// The per-frame body that `ke_render_cluster_create` registers. It ignores its error out-parameter
/// and returns true on every path. Light records are staged in a chunk that is uploaded each time
/// it fills and once more at the end; the records are capped while the totals keep counting, and an
/// overflow is reported once per kind through `logLightOverflow`. A frame without a camera uploads
/// the lights and stops; otherwise it also uploads the cull parameters and the grid and dispatches
/// the compute pipeline.
fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
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
            const pls: [*c]const c.ke_point_light_component = @ptrCast(@alignCast(segs[s].columns[0]));
            const wts: [*c]const c.ke_world_transform_component = @ptrCast(@alignCast(segs[s].columns[1]));
            point_total += segs[s].count;
            var i: usize = 0;
            while (i < segs[s].count and pn < MAX_LIGHTS) : (i += 1) {
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
        logLightOverflow(cm.logger, "point", point_total, MAX_LIGHTS);
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
            const sls: [*c]const SpotLightComp = @ptrCast(@alignCast(segs[s].columns[0]));
            const wts: [*c]const c.ke_world_transform_component = @ptrCast(@alignCast(segs[s].columns[1]));
            spot_total += segs[s].count;
            var i: usize = 0;
            while (i < segs[s].count and sn < MAX_LIGHTS) : (i += 1) {
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
        logLightOverflow(cm.logger, "spot", spot_total, MAX_LIGHTS);
        cm.spot_overflow_warned = true;
    }

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, 2, &cam_segc);
    if (cam_segc == 0 or cam_segs[0].count == 0) return true;
    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_segs[0].columns[0]));

    const pc = core.*.begin_pass.?(core, &cm.cull_io);
    if (pc == null) return true;

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    const depth_from_view_z = cm.view_space.params.?(cm.view_space).depth_from_view_z;
    var frustum: c.ke_camera_frustum = undefined;
    cm.camera.perspective_frustum.?(cm.camera, cam, aspect, &frustum);
    var params: ClusterParams = .{
        .grid = .{ @floatFromInt(cm.grid_x), @floatFromInt(cm.grid_y), @floatFromInt(cm.grid_z), @floatFromInt(cm.max_lights_per_cluster) },
        .counts = .{ @floatFromInt(pn), @floatFromInt(sn), depth_from_view_z, 0.0 },
        .depth = .{ frustum.near_plane, frustum.far_plane, 0.0, 0.0 },
    };
    core.*.upload.?(core, cm.cull_uniform, 0, &params, @sizeOf(ClusterParams));

    uploadGrid(cm, bw, bh, cam.near_plane, cam.far_plane);

    const cp = pc.*.begin_compute.?(pc);
    cp.*.set_pipeline.?(cp, cm.cull_pipeline);
    cm.binder.bind_compute_set.?(cm.binder, cp, cm.cull_set, null, 0);
    cp.*.dispatch.?(cp, (cm.num_clusters + 63) / 64, 1, 1);
    cp.*.end.?(cp);
    core.*.end_pass.?(core, pc);
    return true;
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

fn makeStorageBuffer(dev: *c.ke_gpu_device, label: [*c]const u8, size: usize, out_error: [*c][*c]c.ke_error) c.ke_gpu_buffer {
    return dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .label = label,
        .initial_data = null,
        .size = size,
        .usage = c.KE_GPU_BUFFER_USAGE_STORAGE | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, out_error);
}

/// Runs once, from `ke_render_cluster_create`, before the module is registered. It creates the GPU
/// objects in a fixed order, publishes the light lists and the grid to the render service under the
/// names `feature_bindings` gives them, and fills the access list, which writes the tag imported as "light_clusters",
/// and the queries. A failed step returns false with the error placed in the out-error parameter,
/// and the objects created before it stay set for `destroyModule` to release.
fn setup(cm: *ClusterModule, dev: *c.ke_gpu_device, core: *c.ke_render_service,
             logger: ?*c.ke_logger, grid_x: u32, grid_y: u32, grid_z: u32, max_lights_per_cluster: u32,
             point_light_cid: c.ke_component_id, spot_light_cid: c.ke_component_id,
             world_transform_cid: c.ke_component_id, camera_cid: c.ke_component_id,
             frame_cid: c.ke_component_id, view_space: *c.ke_view_space, render_camera: *c.ke_render_camera,
             out_error: [*c][*c]c.ke_error) bool {
    cm.core = core;
    cm.device = dev;
    cm.logger = logger;
    cm.view_space = view_space;
    cm.camera = render_camera;
    cm.point_light_cid = point_light_cid;
    cm.spot_light_cid = spot_light_cid;
    cm.world_transform_cid = world_transform_cid;
    cm.camera_cid = camera_cid;
    cm.frame_cid = frame_cid;
    cm.grid_x = grid_x;
    cm.grid_y = grid_y;
    cm.grid_z = grid_z;
    cm.max_lights_per_cluster = max_lights_per_cluster;
    cm.num_clusters = grid_x * grid_y * grid_z;

    const point_lights_bytes = MAX_LIGHTS * @sizeOf(PointLightGpu);
    const spot_lights_bytes = MAX_LIGHTS * @sizeOf(SpotLightGpu);
    const indices_bytes: usize = @as(usize, cm.num_clusters) * cm.max_lights_per_cluster * @sizeOf(u32);
    const counts_bytes: usize = @as(usize, cm.num_clusters) * @sizeOf(u32);

    cm.point_lights_sb = makeStorageBuffer(dev, "cluster.point_lights_sb", point_lights_bytes, out_error);
    if (cm.point_lights_sb == c.KE_GPU_INVALID_HANDLE) return false;
    cm.spot_lights_sb = makeStorageBuffer(dev, "cluster.spot_lights_sb", spot_lights_bytes, out_error);
    if (cm.spot_lights_sb == c.KE_GPU_INVALID_HANDLE) return false;
    cm.point_indices_sb = makeStorageBuffer(dev, "cluster.point_indices_sb", indices_bytes, out_error);
    if (cm.point_indices_sb == c.KE_GPU_INVALID_HANDLE) return false;
    cm.point_counts_sb = makeStorageBuffer(dev, "cluster.point_counts_sb", counts_bytes, out_error);
    if (cm.point_counts_sb == c.KE_GPU_INVALID_HANDLE) return false;
    cm.spot_indices_sb = makeStorageBuffer(dev, "cluster.spot_indices_sb", indices_bytes, out_error);
    if (cm.spot_indices_sb == c.KE_GPU_INVALID_HANDLE) return false;
    cm.spot_counts_sb = makeStorageBuffer(dev, "cluster.spot_counts_sb", counts_bytes, out_error);
    if (cm.spot_counts_sb == c.KE_GPU_INVALID_HANDLE) return false;

    cm.cluster_grid_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .label = "cluster.cluster_grid_uniform",
        .initial_data = null,
        .size = @sizeOf(ClusterGridUniform),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, out_error);
    if (cm.cluster_grid_uniform == c.KE_GPU_INVALID_HANDLE) return false;
    const published = [_]struct { buffer: c.ke_gpu_buffer, size: usize }{
        .{ .buffer = cm.point_lights_sb, .size = point_lights_bytes },
        .{ .buffer = cm.spot_lights_sb, .size = spot_lights_bytes },
        .{ .buffer = cm.point_indices_sb, .size = indices_bytes },
        .{ .buffer = cm.point_counts_sb, .size = counts_bytes },
        .{ .buffer = cm.spot_indices_sb, .size = indices_bytes },
        .{ .buffer = cm.spot_counts_sb, .size = counts_bytes },
        .{ .buffer = cm.cluster_grid_uniform, .size = @sizeOf(ClusterGridUniform) },
    };
    for (feature_bindings.cluster_buffers, published) |name, buffer| {
        if (core.*.import_buffer.?(core, name.resource, buffer.buffer, buffer.size, out_error) == c.KE_COMPONENT_INVALID) return false;
    }

    cm.binder = core.*.resource_binder.?(core);
    cm.cull_layout = cm.binder.create_shader_layout.?(cm.binder, &cull_layout_params, out_error);
    if (cm.cull_layout == c.KE_RENDER_BINDING_INVALID) return false;

    cm.cull_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .label = "cluster.cull_uniform",
        .initial_data = null,
        .size = @sizeOf(ClusterParams),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, out_error);
    if (cm.cull_uniform == c.KE_GPU_INVALID_HANDLE) return false;
    const cull_bindings = [_]c.ke_render_shader_binding{
        .{ .name = "params", .buffer = cm.cull_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(ClusterParams), .texture_view = 0, .sampler = 0 },
        .{ .name = "point_lights", .buffer = cm.point_lights_sb, .buffer_offset = 0, .buffer_size = point_lights_bytes, .texture_view = 0, .sampler = 0 },
        .{ .name = "spot_lights", .buffer = cm.spot_lights_sb, .buffer_offset = 0, .buffer_size = spot_lights_bytes, .texture_view = 0, .sampler = 0 },
        .{ .name = "point_indices", .buffer = cm.point_indices_sb, .buffer_offset = 0, .buffer_size = indices_bytes, .texture_view = 0, .sampler = 0 },
        .{ .name = "point_counts", .buffer = cm.point_counts_sb, .buffer_offset = 0, .buffer_size = counts_bytes, .texture_view = 0, .sampler = 0 },
        .{ .name = "spot_indices", .buffer = cm.spot_indices_sb, .buffer_offset = 0, .buffer_size = indices_bytes, .texture_view = 0, .sampler = 0 },
        .{ .name = "spot_counts", .buffer = cm.spot_counts_sb, .buffer_offset = 0, .buffer_size = counts_bytes, .texture_view = 0, .sampler = 0 },
    };
    cm.cull_set = cm.binder.create_set.?(cm.binder, cm.cull_layout, null, "cluster.cull_set", &cull_bindings, cull_bindings.len, out_error);
    if (cm.cull_set == c.KE_RENDER_BINDING_INVALID) return false;

    const cs = core.*.load_shader.?(core, "cluster_cull", c.KE_GPU_SHADER_STAGE_COMPUTE, out_error);
    if (cs == c.KE_GPU_INVALID_HANDLE) return false;

    var cull_pipeline_params = c.ke_gpu_compute_pipeline_params{
        .label = "cluster.cull_pipeline",
        .compute_module = cs,
        .compute_entry = "cs_main",
        .bind_group_layouts = .{ 0, 0, 0, 0 },
        .bind_group_layout_count = 0,
    };
    if (!cm.binder.pipeline_layouts.?(cm.binder, cm.cull_layout, &cull_pipeline_params.bind_group_layouts, cull_pipeline_params.bind_group_layouts.len, &cull_pipeline_params.bind_group_layout_count, out_error)) return false;
    cm.cull_pipeline = dev.create_compute_pipeline.?(dev, &cull_pipeline_params, out_error);
    if (cm.cull_pipeline == c.KE_GPU_INVALID_HANDLE) return false;

    cm.clusters_cid = core.*.import_tag.?(core, "light_clusters", null);
    cm.cull_io = std.mem.zeroes(c.ke_render_pass_io);
    cm.cull_io.name = "render.cull";
    cm.cull_access = .{
        .{ .cid = cm.clusters_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = cm.point_light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = cm.spot_light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = cm.world_transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = cm.camera_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = cm.frame_cid, .access = c.KE_ACCESS_READ },
    };

    const rd = c.KE_ACCESS_READ;
    cm.cull_queries_terms = .{ .{ .cid = cm.point_light_cid, .access = rd }, .{ .cid = cm.world_transform_cid, .access = rd }, .{ .cid = cm.spot_light_cid, .access = rd }, .{ .cid = cm.world_transform_cid, .access = rd }, .{ .cid = cm.camera_cid, .access = rd }, .{ .cid = cm.world_transform_cid, .access = rd } };
    cm.cull_queries = .{ .{ .terms = &cm.cull_queries_terms[0], .term_count = 2 }, .{ .terms = &cm.cull_queries_terms[2], .term_count = 2 }, .{ .terms = &cm.cull_queries_terms[4], .term_count = 2 } };
    return true;
}

/// Releases every GPU object, set and layout whose handle is not the invalid one, so it is safe on a module that
/// `setup` did not finish. The device and the borrowed pointers are not released.
fn destroyModule(cm: *const ClusterModule) void {
    const dev = cm.device;
    const invalid = c.KE_GPU_INVALID_HANDLE;
    if (cm.cull_pipeline != invalid) dev.destroy_compute_pipeline.?(dev, cm.cull_pipeline);
    if (cm.cull_layout != c.KE_RENDER_BINDING_INVALID) {
        cm.binder.destroy_set.?(cm.binder, cm.cull_set);
        cm.binder.destroy_shader_layout.?(cm.binder, cm.cull_layout);
    }
    if (cm.cull_uniform != invalid) dev.destroy_buffer.?(dev, cm.cull_uniform);
    if (cm.cluster_grid_uniform != invalid) dev.destroy_buffer.?(dev, cm.cluster_grid_uniform);
    const storage = [_]c.ke_gpu_buffer{
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
fn destroyHandle(self: ?*c.ke_render_cluster) callconv(.c) void {
    const cm: *ClusterModule = @ptrCast(@alignCast(self orelse return));
    destroyModule(cm);
    gpa.destroy(cm);
}

/// Builds a cluster pass on the render service and device given, and registers its system with the
/// runtime given. The handle's `ref` is null when a required pointer is null, when `setup` fails,
/// or when the runtime refuses the registration; in the last two cases the objects created so far
/// are released. Only failures that `setup` checks reach the out-error parameter.
export fn ke_render_cluster_create(runtime: ?*c.ke_runtime, core: ?*c.ke_render_service,
                                    device: ?*c.ke_gpu_device, logger: ?*c.ke_logger,
                                    grid_x: u32, grid_y: u32, grid_z: u32, max_lights_per_cluster: u32,
                                    point_light_cid: c.ke_component_id, spot_light_cid: c.ke_component_id,
                                    world_transform_cid: c.ke_component_id, camera_cid: c.ke_component_id,
                                    frame_cid: c.ke_component_id, view_space: ?*c.ke_view_space,
                                    render_camera: ?*c.ke_render_camera,
                                    out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_cluster_handle {
    const empty = c.ke_render_cluster_handle{ .ref = null, .destroy = null };
    const rt = runtime orelse return empty;
    const core_ref = core orelse return empty;
    const dev = device orelse return empty;
    const vs = view_space orelse return empty;
    const camera_api = render_camera orelse return empty;

    const cm = gpa.create(ClusterModule) catch return empty;
    cm.* = .{};
    if (!setup(cm, dev, core_ref, logger, grid_x, grid_y, grid_z, max_lights_per_cluster,
               point_light_cid, spot_light_cid, world_transform_cid, camera_cid, frame_cid, vs, camera_api, out_error)) {
        destroyModule(cm);
        gpa.destroy(cm);
        return empty;
    }

    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = "render.cull";
    params.phase = c.KE_PHASE_RENDER;
    params.queries = &cm.cull_queries;
    params.query_count = cm.cull_queries.len;
    params.access_list = &cm.cull_access;
    params.access_count = cm.cull_access.len;
    params.pinned_thread = 0;
    params.user_data = cm;
    params.execute = system;
    if (rt.register_system.?(rt, &params, out_error) == 0) {
        destroyModule(cm);
        gpa.destroy(cm);
        return empty;
    }

    return .{ .ref = @ptrCast(cm), .destroy = destroyHandle };
}

const testing = std.testing;

const Stubs = @import("stubs").Stubs(c);

test "creating and destroying the cluster pass leaves no block allocated and no GPU resource live" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var camera = std.mem.zeroes(c.ke_render_camera);
    var view_space = std.mem.zeroes(c.ke_view_space);
    const h = ke_render_cluster_create(rt.api(), core.api(), dev.api(), null, 16, 9, 24, 64, 1, 2, 3, 4, 5, &view_space, &camera, null);
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try testing.expectEqual(@as(i64, 0), dev.compute_live);
    try heap.expectNoLeaks();
}

test "a cluster pass whose shader fails to load releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    core.shader_loads_fail = true;
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var camera = std.mem.zeroes(c.ke_render_camera);
    var view_space = std.mem.zeroes(c.ke_view_space);
    const h = ke_render_cluster_create(rt.api(), core.api(), dev.api(), null, 16, 9, 24, 64, 1, 2, 3, 4, 5, &view_space, &camera, null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try testing.expectEqual(@as(i64, 0), dev.compute_live);
    try heap.expectNoLeaks();
}

test "a cluster pass the runtime refuses to register releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    rt.limit = 0;
    var camera = std.mem.zeroes(c.ke_render_camera);
    var view_space = std.mem.zeroes(c.ke_view_space);
    const h = ke_render_cluster_create(rt.api(), core.api(), dev.api(), null, 16, 9, 24, 64, 1, 2, 3, 4, 5, &view_space, &camera, null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try testing.expectEqual(@as(i64, 0), dev.compute_live);
    try heap.expectNoLeaks();
}
