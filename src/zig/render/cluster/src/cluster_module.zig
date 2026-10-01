const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;

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
    proj: [4]f32,
    view: [16]f32,
};

const ClusterModule = struct {
    core: *c.ke_render_service = undefined,
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

    light_set_bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE,
    fwd_light_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    cluster_grid_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,

    point_lights_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    spot_lights_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    point_indices_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    point_counts_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    spot_indices_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    spot_counts_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,

    cull_pipeline: c.ke_gpu_pipeline = c.KE_GPU_INVALID_HANDLE,
    cull_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    cull_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    cull_io: c.ke_render_pass_io = undefined,
    cull_access: [6]c.ke_component_access = undefined,
    cull_queries: [3]c.ke_query_decl = undefined,
    clusters_cid: c.ke_component_id = undefined,

    point_overflow_warned: bool = false,
    spot_overflow_warned: bool = false,
};

fn logLightOverflow(logger: ?*c.ke_logger, kind: []const u8, total: usize, cap: usize) void {
    const lg = logger orelse return;
    var buf: [192]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "{s} light count ({d}) exceeds the storage capacity ({d}); only the first {d} are culled/shaded this run", .{ kind, total, cap, cap }) catch return;
    var ev = c.ke_log_event{ .level = c.KE_LOG_LEVEL_WARNING, .tag = "render_service", .message = msg.ptr };
    lg.log.?(lg, &ev);
}

inline fn moduleOf(user: ?*anyopaque) *ClusterModule {
    return @alignCast(@ptrCast(user.?));
}

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
        const segs = c.ke_system_ctx_view(ctx, 0, &segc);
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
        const segs = c.ke_system_ctx_view(ctx, 1, &segc);
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
    const cam_segs = c.ke_system_ctx_view(ctx, 2, &cam_segc);
    if (cam_segc == 0 or cam_segs[0].count == 0) return true;
    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_segs[0].columns[0]));
    const cam_wt: *const c.ke_world_transform_component = @ptrCast(@alignCast(cam_segs[0].columns[1]));

    const pc = core.*.begin_pass.?(core, ctx, &cm.cull_io);
    if (pc == null) return true;

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    const depth_from_view_z = cm.view_space.params.?(cm.view_space).depth_from_view_z;
    var frustum: c.ke_camera_frustum = undefined;
    cm.camera.perspective_frustum.?(cm.camera, cam, aspect, &frustum);
    var view_m: c.ke_mat4 = undefined;
    cm.camera.view.?(cm.camera, &cam_wt.matrix, &view_m);
    var params: ClusterParams = .{
        .grid = .{ @floatFromInt(cm.grid_x), @floatFromInt(cm.grid_y), @floatFromInt(cm.grid_z), @floatFromInt(cm.max_lights_per_cluster) },
        .counts = .{ @floatFromInt(pn), @floatFromInt(sn), depth_from_view_z, 0.0 },
        .proj = .{ frustum.tan_half_fov_y, frustum.aspect, frustum.near_plane, frustum.far_plane },
        .view = view_m.m,
    };
    core.*.upload.?(core, cm.cull_uniform, 0, &params, @sizeOf(ClusterParams));

    uploadGrid(cm, bw, bh, cam.near_plane, cam.far_plane);

    const cp = pc.*.begin_compute.?(pc);
    cp.*.set_pipeline.?(cp, cm.cull_pipeline);
    cp.*.set_bind_group.?(cp, 0, cm.cull_bind_group, null, 0);
    cp.*.dispatch.?(cp, (cm.num_clusters + 63) / 64, 1, 1);
    cp.*.end.?(cp);
    core.*.end_pass.?(core, pc);
    return true;
}

fn uploadGrid(cm: *const ClusterModule, bw: u32, bh: u32, near: f32, far: f32) void {
    const core = cm.core;
    const grid_data = ClusterGridUniform{
        .cluster_grid = .{ @floatFromInt(cm.grid_x), @floatFromInt(cm.grid_y), @floatFromInt(cm.grid_z), @floatFromInt(cm.max_lights_per_cluster) },
        .cluster_viewport = .{ @floatFromInt(bw), @floatFromInt(bh), near, far },
        .view_space = .{ cm.view_space.params.?(cm.view_space).depth_from_view_z, 0.0, 0.0, 0.0 },
    };
    core.*.upload.?(core, cm.cluster_grid_uniform, 0, &grid_data, @sizeOf(ClusterGridUniform));
}

fn makeStorageBuffer(dev: *c.ke_gpu_device, size: usize, out_error: [*c][*c]c.ke_error) c.ke_gpu_buffer {
    return dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = size,
        .usage = c.KE_GPU_BUFFER_USAGE_STORAGE | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
}

fn setup(cm: *ClusterModule, dev: *c.ke_gpu_device, core: *c.ke_render_service,
             logger: ?*c.ke_logger, grid_x: u32, grid_y: u32, grid_z: u32, max_lights_per_cluster: u32,
             point_light_cid: c.ke_component_id, spot_light_cid: c.ke_component_id,
             world_transform_cid: c.ke_component_id, camera_cid: c.ke_component_id,
             frame_cid: c.ke_component_id, view_space: *c.ke_view_space, render_camera: *c.ke_render_camera,
             out_error: [*c][*c]c.ke_error) bool {
    cm.core = core;
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

    cm.point_lights_sb = makeStorageBuffer(dev, point_lights_bytes, out_error);
    if (cm.point_lights_sb == c.KE_GPU_INVALID_HANDLE) return false;
    cm.spot_lights_sb = makeStorageBuffer(dev, spot_lights_bytes, out_error);
    if (cm.spot_lights_sb == c.KE_GPU_INVALID_HANDLE) return false;
    cm.point_indices_sb = makeStorageBuffer(dev, indices_bytes, out_error);
    if (cm.point_indices_sb == c.KE_GPU_INVALID_HANDLE) return false;
    cm.point_counts_sb = makeStorageBuffer(dev, counts_bytes, out_error);
    if (cm.point_counts_sb == c.KE_GPU_INVALID_HANDLE) return false;
    cm.spot_indices_sb = makeStorageBuffer(dev, indices_bytes, out_error);
    if (cm.spot_indices_sb == c.KE_GPU_INVALID_HANDLE) return false;
    cm.spot_counts_sb = makeStorageBuffer(dev, counts_bytes, out_error);
    if (cm.spot_counts_sb == c.KE_GPU_INVALID_HANDLE) return false;

    const ro = c.KE_GPU_BINDING_TYPE_READONLY_STORAGE_BUFFER;
    const frag = c.KE_GPU_SHADER_STAGE_FRAGMENT;
    const light_bgl_entries = [_]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = frag, .type = ro, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 1, .visibility = frag, .type = ro, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 2, .visibility = frag, .type = ro, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 3, .visibility = frag, .type = ro, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 4, .visibility = frag, .type = ro, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 5, .visibility = frag, .type = ro, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 6, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    cm.light_set_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 7,
        .entries = &light_bgl_entries,
    });
    cm.cluster_grid_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = @sizeOf(ClusterGridUniform),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (cm.cluster_grid_uniform == c.KE_GPU_INVALID_HANDLE) return false;
    const light_bg_entries = [_]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = ro, .buffer = cm.point_lights_sb, .buffer_offset = 0, .buffer_size = point_lights_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 1, .type = ro, .buffer = cm.spot_lights_sb, .buffer_offset = 0, .buffer_size = spot_lights_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 2, .type = ro, .buffer = cm.point_indices_sb, .buffer_offset = 0, .buffer_size = indices_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 3, .type = ro, .buffer = cm.point_counts_sb, .buffer_offset = 0, .buffer_size = counts_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 4, .type = ro, .buffer = cm.spot_indices_sb, .buffer_offset = 0, .buffer_size = indices_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 5, .type = ro, .buffer = cm.spot_counts_sb, .buffer_offset = 0, .buffer_size = counts_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 6, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = cm.cluster_grid_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(ClusterGridUniform), .texture_view = 0, .sampler = 0 },
    };
    cm.fwd_light_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = cm.light_set_bgl,
        .entry_count = 7,
        .entries = &light_bg_entries,
    }, out_error);
    if (cm.fwd_light_bind_group == c.KE_GPU_INVALID_HANDLE) return false;
    _ = core.*.import_bind_group.?(core, "cluster_lights", cm.fwd_light_bind_group, cm.light_set_bgl, null);

    const rw = c.KE_GPU_BINDING_TYPE_STORAGE_BUFFER;
    const comp = c.KE_GPU_SHADER_STAGE_COMPUTE;
    const cull_bgl_entries = [_]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = comp, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 1, .visibility = comp, .type = ro, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 2, .visibility = comp, .type = ro, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 3, .visibility = comp, .type = rw, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 4, .visibility = comp, .type = rw, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 5, .visibility = comp, .type = rw, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 6, .visibility = comp, .type = rw, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    const cull_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 7,
        .entries = &cull_bgl_entries,
    });

    cm.cull_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = @sizeOf(ClusterParams),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (cm.cull_uniform == c.KE_GPU_INVALID_HANDLE) return false;
    const cull_bg_entries = [_]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = cm.cull_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(ClusterParams), .texture_view = 0, .sampler = 0 },
        .{ .binding = 1, .type = ro, .buffer = cm.point_lights_sb, .buffer_offset = 0, .buffer_size = point_lights_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 2, .type = ro, .buffer = cm.spot_lights_sb, .buffer_offset = 0, .buffer_size = spot_lights_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 3, .type = rw, .buffer = cm.point_indices_sb, .buffer_offset = 0, .buffer_size = indices_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 4, .type = rw, .buffer = cm.point_counts_sb, .buffer_offset = 0, .buffer_size = counts_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 5, .type = rw, .buffer = cm.spot_indices_sb, .buffer_offset = 0, .buffer_size = indices_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 6, .type = rw, .buffer = cm.spot_counts_sb, .buffer_offset = 0, .buffer_size = counts_bytes, .texture_view = 0, .sampler = 0 },
    };
    cm.cull_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = cull_bgl,
        .entry_count = 7,
        .entries = &cull_bg_entries,
    }, out_error);
    if (cm.cull_bind_group == c.KE_GPU_INVALID_HANDLE) return false;

    const cs = core.*.load_shader.?(core, "cluster_cull", c.KE_GPU_SHADER_STAGE_COMPUTE, out_error);
    if (cs == c.KE_GPU_INVALID_HANDLE) return false;

    const cull_layouts = [_]c.ke_gpu_bind_group_layout{ cull_bgl, 0, 0, 0 };
    cm.cull_pipeline = dev.create_compute_pipeline.?(dev, &c.ke_gpu_compute_pipeline_params{
        .compute_module = cs,
        .compute_entry = "cs_main",
        .bind_group_layouts = cull_layouts,
        .bind_group_layout_count = 1,
    });
    if (cm.cull_pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "cull pass: compute pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    cm.clusters_cid = core.*.import_tag.?(core, "light_clusters", null);
    cm.cull_io = std.mem.zeroes(c.ke_render_pass_io);
    cm.cull_io.cmd_slot = 2;
    cm.cull_access = .{
        .{ .cid = cm.clusters_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = cm.point_light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = cm.spot_light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = cm.world_transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = cm.camera_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = cm.frame_cid, .access = c.KE_ACCESS_READ },
    };

    const rd = c.KE_ACCESS_READ;
    cm.cull_queries = std.mem.zeroes([3]c.ke_query_decl);
    cm.cull_queries[0].terms[0] = .{ .cid = cm.point_light_cid, .access = rd };
    cm.cull_queries[0].terms[1] = .{ .cid = cm.world_transform_cid, .access = rd };
    cm.cull_queries[0].term_count = 2;
    cm.cull_queries[1].terms[0] = .{ .cid = cm.spot_light_cid, .access = rd };
    cm.cull_queries[1].terms[1] = .{ .cid = cm.world_transform_cid, .access = rd };
    cm.cull_queries[1].term_count = 2;
    cm.cull_queries[2].terms[0] = .{ .cid = cm.camera_cid, .access = rd };
    cm.cull_queries[2].terms[1] = .{ .cid = cm.world_transform_cid, .access = rd };
    cm.cull_queries[2].term_count = 2;
    return true;
}

fn destroyHandle(self: ?*c.ke_render_cluster) callconv(.c) void {
    const cm: *ClusterModule = @ptrCast(@alignCast(self orelse return));
    gpa.destroy(cm);
}

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
    _ = rt.register_system.?(rt, &params, null);

    return .{ .ref = @ptrCast(cm), .destroy = destroyHandle };
}
