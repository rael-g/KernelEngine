const std = @import("std");
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;

const gpa = std.heap.c_allocator;

// Clustered light cull — bins point/spot lights into a froxel grid so a shading
// pass iterates only the lights touching its pixel. A standalone plugin: talks
// to the rest of the render pipeline only through the borrowed
// ke_render_core/ke_runtime handles passed to create() — it never sees another
// pass's private struct. Publishes its outputs ("cluster_lights" bind group +
// layout, "light_clusters" ordering tag) through the named-resource table;
// deferred/forward resolve them by name. Uploads its own grid UBO inside its
// own system() (using the camera it already reads for the cull), so no other
// pass needs to trigger it.

// Duplicated from render_module.zig rather than shared, matching the
// decoupling precedent already established in cluster_feature.slang (its own
// header comment: "Duplicated rather than shared via import to keep this
// feature decoupled from the pass file").
// MAX_LIGHTS is a storage-buffer capacity ceiling, not a performance limit —
// the brute-force cull (O(clusters × lights), no spatial acceleration) has no
// throughput cliff of its own; it degrades linearly. The real ceiling for how
// many lights run acceptably is discovered empirically (frame time).
const MAX_LIGHTS = 1_000_000; // point (or spot) lights the storage buffers can hold, each type independently
// Lights packed into a stack chunk and uploaded whole, bounding both stack use
// (SpotLightGpu is 64B → 64KB here) and the number of per-frame upload records.
const UPLOAD_CHUNK = 1024;

// One point light in the storage buffer (matches cluster_cull/forward PointLight).
const PointLightGpu = extern struct {
    pos_radius: [4]f32, // xyz = world position, w = radius
    color_intensity: [4]f32, // rgb = color, w = intensity
};

// One spot light in the storage buffer (cone cosines precomputed).
const SpotLightGpu = extern struct {
    pos_range: [4]f32, // xyz = world position, w = range
    dir_cos_inner: [4]f32, // xyz = cone axis, w = cos(inner angle)
    color_intensity: [4]f32, // rgb = color, w = intensity
    cone: [4]f32, // x = cos(outer angle); yzw pad
};

// Mirrors the C# PointLightComponent { Vector3 Color, float Intensity, float Radius }
// (registered as "point_light"). NOTE the field order is the C# struct's, not the
// kernel ke_point_light_component header (which orders them differently).
// Exported: render_module.zig registers the component (its cid is shared with
// forward's own access list), so it needs this struct's size at registration.
const PointLightComp = extern struct {
    color: [3]f32,
    intensity: f32,
    radius: f32,
};

// Mirrors the C# SpotLightComponent { Vector3 Direction, Vector3 Color, float
// Intensity, float Range, float InnerAngleDeg, float OuterAngleDeg } (registered
// "spot_light"). Field order is the C# struct's, not the kernel header's.
const SpotLightComp = extern struct {
    dir: [3]f32,
    color: [3]f32,
    intensity: f32,
    range: f32,
    inner_deg: f32,
    outer_deg: f32,
};

// The clustered-lights feature's own UBO (cluster_feature.slang, set 3 binding
// 6). Kept out of the shared per-frame UBO: a scene with no dynamic-light
// module needs no cluster grid data at all.
const ClusterGridUniform = extern struct {
    cluster_grid: [4]f32, // numX, numY, numZ, maxLightsPerCluster
    cluster_viewport: [4]f32, // screen W, screen H, near, far
};

// The cull compute uniform (matches cluster_cull.slang ClusterParams).
const ClusterParams = extern struct {
    grid: [4]f32, // numX, numY, numZ, maxLightsPerCluster
    counts: [4]f32, // pointCount, spotCount, 0, 0
    proj: [4]f32, // tan(fovY/2), aspect, near, far
    view: [16]f32, // world → view
};

const ClusterModule = struct {
    // Borrowed cross-cutting refs, captured once at setup so the system body
    // never reaches into the parent ModuleState.
    core: *c.ke_render_core = undefined,
    logger: ?*c.ke_logger = null,
    point_light_cid: c.ke_component_id = undefined,
    spot_light_cid: c.ke_component_id = undefined,
    transform_cid: c.ke_component_id = undefined,
    camera_cid: c.ke_component_id = undefined,
    frame_cid: c.ke_component_id = undefined,

    // Clustered-forward grid + per-froxel cap — caller-configurable workload
    // shape (see ke_render_cluster_params), not an engine-imposed limit.
    grid_x: u32 = undefined,
    grid_y: u32 = undefined,
    grid_z: u32 = undefined,
    num_clusters: u32 = undefined,
    max_lights_per_cluster: u32 = undefined,

    // Set 3 — clustered light lists (forward reads what the cull pass wrote) +
    // the cluster-grid UBO (cluster_feature.slang's accumulate_clustered_lights
    // hook) at binding 6.
    light_set_bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE,
    fwd_light_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    cluster_grid_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,

    // Storage buffers shared by the cull pass (writes) and the forward (reads).
    point_lights_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    spot_lights_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    point_indices_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    point_counts_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    spot_indices_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    spot_counts_sb: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,

    // Light cull compute pass.
    cull_pipeline: c.ke_gpu_pipeline = c.KE_GPU_INVALID_HANDLE,
    cull_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    cull_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    cull_io: c.ke_render_pass_io = undefined,
    cull_access: [6]c.ke_component_access = undefined,
    cull_queries: [3]c.ke_query_decl = undefined, // [point_light,transform], [spot_light,transform], [camera,transform]
    clusters_cid: c.ke_component_id = undefined, // tag: cull WRITES, forward READS (ordering)

    // Latched once the scene's actual point/spot count exceeds MAX_LIGHTS, so
    // the truncation warning prints exactly once instead of every frame.
    point_overflow_warned: bool = false,
    spot_overflow_warned: bool = false,
};

// Left-handed view from a camera transform (identity rotation → look at origin;
// otherwise the world-matrix basis, looking down local −Z). Duplicated from
// render_module.zig (same decoupling precedent as the constants above) so the
// cull pass agrees with the forward on view space without importing it.
fn cameraView(cam_tc: *const c.ke_transform_component) zm.Mat {
    const eye = zm.f32x4(cam_tc.position.x, cam_tc.position.y, cam_tc.position.z, 1.0);
    const q = cam_tc.rotation;
    const view = if (@abs(q.x) < 1e-6 and @abs(q.y) < 1e-6 and @abs(q.z) < 1e-6)
        zm.lookAtLh(eye, zm.f32x4(0, 0, 0, 1), zm.f32x4(0, 1, 0, 0))
    else blk: {
        const m = cam_tc.world_matrix.m;
        const fwd = zm.f32x4(-m[8], -m[9], -m[10], 0);
        const up = zm.f32x4(m[4], m[5], m[6], 0);
        break :blk zm.lookToLh(eye, fwd, up);
    };
    // Reflect view-space X so world +X reads to the right, matching the forward
    // pass's camera view — light binning must use the identical view or clustered
    // lights land on the wrong screen half.
    return zm.mul(view, zm.scaling(-1.0, 1.0, 1.0));
}

fn logLightOverflow(logger: ?*c.ke_logger, kind: []const u8, total: usize, cap: usize) void {
    const lg = logger orelse return;
    var buf: [192]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "{s} light count ({d}) exceeds the storage capacity ({d}); only the first {d} are culled/shaded this run", .{ kind, total, cap, cap }) catch return;
    var ev = c.ke_log_event{ .level = c.KE_LOG_LEVEL_WARNING, .tag = "render_core", .message = msg.ptr };
    lg.log.?(lg, &ev);
}

inline fn moduleOf(user: ?*anyopaque) *ClusterModule {
    return @alignCast(@ptrCast(user.?));
}

// Packs the scene's point + spot lights into storage buffers, then dispatches one
// thread per cluster to bin them. The forward reads the result; the "light_clusters"
// tag orders this pass before it.
fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const cm = moduleOf(user);
    const core = cm.core;
    const deg2rad: f32 = std.math.pi / 180.0;
    // Pack point lights — view 0 = [point_light, transform], columns aligned.
    // Batched: fill a stack chunk and upload it whole, so N lights cost ceil(N /
    // UPLOAD_CHUNK) uploads instead of N — a per-light upload blows the render
    // core's per-frame upload-record cap (and is slow) at a few thousand lights.
    var pn: u32 = 0;
    var point_total: usize = 0;
    {
        var chunk: [UPLOAD_CHUNK]PointLightGpu = undefined;
        var fill: u32 = 0;
        var segc: usize = 0;
        const segs = c.ke_system_ctx_view(ctx, 0, &segc);
        var s: usize = 0;
        while (s < segc) : (s += 1) {
            const pls: [*c]const PointLightComp = @ptrCast(@alignCast(segs[s].columns[0]));
            const tcs: [*c]const c.ke_transform_component = @ptrCast(@alignCast(segs[s].columns[1]));
            point_total += segs[s].count;
            var i: usize = 0;
            while (i < segs[s].count and pn < MAX_LIGHTS) : (i += 1) {
                const m = tcs[i].world_matrix.m;
                chunk[fill] = PointLightGpu{
                    .pos_radius = .{ m[12], m[13], m[14], pls[i].radius },
                    .color_intensity = .{ pls[i].color[0], pls[i].color[1], pls[i].color[2], pls[i].intensity },
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
    // A scene with more lights than MAX_LIGHTS is silently truncated by the
    // cap above (pn stops advancing) unless this fires: log once, not every
    // frame, so nobody mistakes a capped run for the full requested count.
    if (point_total > MAX_LIGHTS and !cm.point_overflow_warned) {
        logLightOverflow(cm.logger, "point", point_total, MAX_LIGHTS);
        cm.point_overflow_warned = true;
    }

    // Pack spot lights — view 1 = [spot_light, transform]; cone cosines precomputed.
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
            const tcs: [*c]const c.ke_transform_component = @ptrCast(@alignCast(segs[s].columns[1]));
            spot_total += segs[s].count;
            var i: usize = 0;
            while (i < segs[s].count and sn < MAX_LIGHTS) : (i += 1) {
                const m = tcs[i].world_matrix.m;
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

    // Camera → view + projection params (must match the forward's). View 2 =
    // [camera, transform]; the first match is the active camera.
    var cam_segc: usize = 0;
    const cam_segs = c.ke_system_ctx_view(ctx, 2, &cam_segc);
    if (cam_segc == 0 or cam_segs[0].count == 0) return;
    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_segs[0].columns[0]));
    const cam_tc: *const c.ke_transform_component = @ptrCast(@alignCast(cam_segs[0].columns[1]));

    const pc = core.*.begin_pass.?(core, ctx, &cm.cull_io);
    if (pc == null) return;

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    var params: ClusterParams = .{
        .grid = .{ @floatFromInt(cm.grid_x), @floatFromInt(cm.grid_y), @floatFromInt(cm.grid_z), @floatFromInt(cm.max_lights_per_cluster) },
        .counts = .{ @floatFromInt(pn), @floatFromInt(sn), 0.0, 0.0 },
        .proj = .{ std.math.tan(cam.fov * deg2rad * 0.5), aspect, cam.near_plane, cam.far_plane },
        .view = undefined,
    };
    zm.storeMat(params.view[0..], cameraView(cam_tc));
    core.*.upload.?(core, cm.cull_uniform, 0, &params, @sizeOf(ClusterParams));

    // The clustered-lights feature's own grid UBO (cluster_feature.slang, set 3
    // binding 6) needs the same bw/bh/near/far this pass already computed for
    // the cull params — uploaded here so no other pass needs to know this
    // module's camera math or private fields to trigger it.
    uploadGrid(cm, bw, bh, cam.near_plane, cam.far_plane);

    const cp = pc.*.begin_compute.?(pc);
    cp.*.set_pipeline.?(cp, cm.cull_pipeline);
    cp.*.set_bind_group.?(cp, 0, cm.cull_bind_group, null, 0);
    cp.*.dispatch.?(cp, (cm.num_clusters + 63) / 64, 1, 1);
    cp.*.end.?(cp);
    core.*.end_pass.?(core, pc);
}

// Uploads the clustered-lights feature's own grid UBO (cluster_feature.slang,
// set 3 binding 6). The shading pass calls this once per frame — the seam
// exists because the grid's screen-size component (viewport) is only known from
// that pass's own backbuffer query.
fn uploadGrid(cm: *const ClusterModule, bw: u32, bh: u32, near: f32, far: f32) void {
    const core = cm.core;
    const grid_data = ClusterGridUniform{
        .cluster_grid = .{ @floatFromInt(cm.grid_x), @floatFromInt(cm.grid_y), @floatFromInt(cm.grid_z), @floatFromInt(cm.max_lights_per_cluster) },
        .cluster_viewport = .{ @floatFromInt(bw), @floatFromInt(bh), near, far },
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

// Storage buffers + the cull compute pipeline + the forward's set-3 light bind
// group. The cull pass writes the per-cluster index lists; the forward reads them.
fn setup(cm: *ClusterModule, dev: *c.ke_gpu_device, core: *c.ke_render_core,
             logger: ?*c.ke_logger, grid_x: u32, grid_y: u32, grid_z: u32, max_lights_per_cluster: u32,
             point_light_cid: c.ke_component_id, spot_light_cid: c.ke_component_id,
             transform_cid: c.ke_component_id, camera_cid: c.ke_component_id,
             frame_cid: c.ke_component_id, out_error: [*c][*c]c.ke_error) bool {
    cm.core = core;
    cm.logger = logger;
    cm.point_light_cid = point_light_cid;
    cm.spot_light_cid = spot_light_cid;
    cm.transform_cid = transform_cid;
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

    // A froxel index/count buffer sized from the caller-configured grid + cap
    // (ke_render_cluster_params) can exceed this device's binding-size limit —
    // that is a legitimate ke_error (this device, at this workload, can't do
    // it), not an engine-imposed ceiling; the caller decides how to react.
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

    // Set 3 — the forward's read-only view of the light + cluster buffers.
    const ro = c.KE_GPU_BINDING_TYPE_READONLY_STORAGE_BUFFER;
    const frag = c.KE_GPU_SHADER_STAGE_FRAGMENT;
    const light_bgl_entries = [_]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = frag, .type = ro, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 1, .visibility = frag, .type = ro, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 2, .visibility = frag, .type = ro, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 3, .visibility = frag, .type = ro, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 4, .visibility = frag, .type = ro, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 5, .visibility = frag, .type = ro, .has_dynamic_offset = 0, .view_dimension = 0 },
        // Clustered-lights feature's own grid UBO (cluster_feature.slang).
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
    // Published under a name so deferred/forward bind it without holding a
    // pointer to *ClusterModule.
    _ = core.*.import_bind_group.?(core, "cluster_lights", cm.fwd_light_bind_group, cm.light_set_bgl, null);

    // Cull compute: uniform + read-only lights + read-write index/count buffers.
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

    // Neither the path nor the shader format is named here — core.load_shader
    // resolves both. The core owns the result; this pass never destroys it.
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

    // Ordering tag: the cull pass WRITES it, deferred/forward READ it (cull →
    // shading) — published through the named-resource table (import_tag) so a
    // consumer looks it up by name via core.cid() instead of a *ClusterModule
    // pointer. No GPU payload; the real light data crosses via "cluster_lights"
    // (import_bind_group) below.
    cm.clusters_cid = core.*.import_tag.?(core, "light_clusters", null);
    cm.cull_io = std.mem.zeroes(c.ke_render_pass_io);
    cm.cull_io.cmd_slot = 2; // cull → frame command slot 2 (before forward)
    // The cull WRITES light_clusters and the forward READS it (cull → forward) —
    // the only ordering the cull needs. It may share a wave with the clear/shadow
    // render passes: the render core accumulates this compute pass's recording into
    // a CPU command list and replays it single-threaded at end_frame, so the unsafe
    // compute∥render recording never actually happens concurrently.
    cm.cull_access = .{
        .{ .cid = cm.clusters_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = cm.point_light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = cm.spot_light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = cm.transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = cm.camera_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = cm.frame_cid, .access = c.KE_ACCESS_READ },
    };

    // Data the cull body reads through resolved views: each light kind paired with
    // its transform, and the camera paired with its transform. Index order here is
    // the query_index the body passes to ke_system_ctx_view.
    const rd = c.KE_ACCESS_READ;
    cm.cull_queries = std.mem.zeroes([3]c.ke_query_decl);
    cm.cull_queries[0].terms[0] = .{ .cid = cm.point_light_cid, .access = rd };
    cm.cull_queries[0].terms[1] = .{ .cid = cm.transform_cid, .access = rd };
    cm.cull_queries[0].term_count = 2;
    cm.cull_queries[1].terms[0] = .{ .cid = cm.spot_light_cid, .access = rd };
    cm.cull_queries[1].terms[1] = .{ .cid = cm.transform_cid, .access = rd };
    cm.cull_queries[1].term_count = 2;
    cm.cull_queries[2].terms[0] = .{ .cid = cm.camera_cid, .access = rd };
    cm.cull_queries[2].terms[1] = .{ .cid = cm.transform_cid, .access = rd };
    cm.cull_queries[2].term_count = 2;
    return true;
}

fn destroyHandle(self: ?*c.ke_render_cluster) callconv(.c) void {
    const cm: *ClusterModule = @ptrCast(@alignCast(self orelse return));
    gpa.destroy(cm);
}

export fn ke_render_cluster_create(runtime: ?*c.ke_runtime, core: ?*c.ke_render_core,
                                    device: ?*c.ke_gpu_device, logger: ?*c.ke_logger,
                                    grid_x: u32, grid_y: u32, grid_z: u32, max_lights_per_cluster: u32,
                                    point_light_cid: c.ke_component_id, spot_light_cid: c.ke_component_id,
                                    transform_cid: c.ke_component_id, camera_cid: c.ke_component_id,
                                    frame_cid: c.ke_component_id,
                                    out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_cluster_handle {
    const empty = c.ke_render_cluster_handle{ .ref = null, .destroy = null };
    const rt = runtime orelse return empty;
    const core_ref = core orelse return empty;
    const dev = device orelse return empty;

    const cm = gpa.create(ClusterModule) catch return empty;
    cm.* = .{};
    if (!setup(cm, dev, core_ref, logger, grid_x, grid_y, grid_z, max_lights_per_cluster,
               point_light_cid, spot_light_cid, transform_cid, camera_cid, frame_cid, out_error)) {
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
