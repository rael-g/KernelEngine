const std = @import("std");
const zm = @import("zmath");

// Compiled into the ke_render_core library (folded here because a separate Zig
// DLL cannot link another Zig DLL's import lib on Windows). Calls the render
// core factory in-lib; the device is caller-created and borrowed.
pub const c = @cImport({
    @cInclude("kernel_engine/runtime/runtime.h");
    @cInclude("kernel_engine/runtime/system_ctx.h");
    @cInclude("kernel_engine/ecs/ke_ecs.h");
    @cInclude("kernel_engine/spatial/transform.h");
    @cInclude("kernel_engine/render/components.h");
    @cInclude("kernel_engine/render/gpu_device.h");
    @cInclude("kernel_engine/render/gpu_commands.h");
    @cInclude("kernel_engine/render/core/render_core.h");
    @cInclude("kernel_engine/render/core/pass_context.h");
    @cInclude("kernel_engine/render/core/render_core_create.h");
    @cInclude("kernel_engine/render/core/render_module_create.h");
});

const gpa = std.heap.c_allocator;

const ExecFn = ?*const fn (?*c.ke_system_ctx, ?*anyopaque, f32) callconv(.c) void;

// The forward pass shaders, compiled Slang -> WGSL by CMake (one module per
// stage; a cross-stage uniform can't be declared twice in one WGSL module).
const forward_vs_wgsl = @embedFile("forward.vs.wgsl");
const forward_fs_wgsl = @embedFile("forward.fs.wgsl");
const skybox_vs_wgsl = @embedFile("skybox.vs.wgsl");
const skybox_fs_wgsl = @embedFile("skybox.fs.wgsl");
const shadow_vs_wgsl = @embedFile("shadow.vs.wgsl");
const shadow_fs_wgsl = @embedFile("shadow.fs.wgsl");
const cluster_cull_cs_wgsl = @embedFile("cluster_cull.cs.wgsl");

const SHADOW_RES = 1024; // shadow map resolution

// Clustered forward grid (froxels): numX×numY screen tiles × numZ depth slices.
const GRID_X = 16;
const GRID_Y = 8;
const GRID_Z = 24;
const NUM_CLUSTERS = GRID_X * GRID_Y * GRID_Z;
const MAX_LIGHTS_PER_CLUSTER = 64;
const MAX_LIGHTS = 256; // total point or spot lights culled per frame

const MAX_DRAWS = 512;
const UNIFORM_STRIDE = 256; // dynamic-offset alignment (>= minUniformBufferOffsetAlignment)

// Set 2 — per-object transform (dynamic offset). Matches forward.slang PerObject.
const PerObject = extern struct {
    mvp: [16]f32,
    model: [16]f32,
};

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

// Set 0 — per-frame camera + light + skybox view. Matches forward.slang PerFrame.
const PerFrame = extern struct {
    camera_pos: [4]f32,
    light_dir: [4]f32,
    light_color: [4]f32, // rgb, w = intensity
    ambient: [4]f32,
    sky_view_proj: [16]f32, // rotation-only view*proj for the skybox
    light_vp: [16]f32, // directional light view*proj (for shadow sampling)
    shadow_params: [4]f32, // x = shadow active, z = directional active
    view: [16]f32, // world→view (for the fragment's cluster z slice)
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

// Mirrors the C# PointLightComponent { Vector3 Color, float Intensity, float Radius }
// (registered as "point_light"). NOTE the field order is the C# struct's, not the
// kernel ke_point_light_component header (which orders them differently).
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

// Mirrors the C# AmbientLightComponent { Vector3 Color } (registered "AmbientLight").
const AmbientComp = extern struct { color: [3]f32 };

// Unit cube positions (8 corners) + indices for the skybox.
const sky_verts = [_]f32{
    -1, -1, -1, 1, -1, -1, 1, 1, -1, -1, 1, -1,
    -1, -1, 1,  1, -1, 1,  1, 1, 1,  -1, 1, 1,
};
const sky_idx = [_]u16{
    0, 1, 2, 0, 2, 3, // -Z
    4, 6, 5, 4, 7, 6, // +Z
    0, 4, 5, 0, 5, 1, // -Y
    3, 2, 6, 3, 6, 7, // +Y
    0, 3, 7, 0, 7, 4, // -X
    1, 5, 6, 1, 6, 2, // +X
};

// Mirrors ke_directional_light_component (10 floats, see render/components.h).
const DirLight = extern struct {
    dir: [3]f32,
    rgb: [3]f32,
    intensity: f32,
    ambient: [3]f32,
};

// The device is borrowed (caller-owned); only the render core is owned here.
const ModuleState = struct {
    core: c.ke_render_core_handle,
    device: *c.ke_gpu_device,
    ndc: c.ke_ndc_convention, // backend clip-space convention (queried at setup)

    bb_writes: [1][*c]const u8,
    io: c.ke_render_pass_io,
    // Frame barrier: begin_frame WRITES "frame", every pass READS it, end_frame
    // WRITES it (write-after-read). W→R→W brackets all passes into one frame so
    // begin (clears the slot table + acquires the backbuffer) strictly precedes
    // every pass and end (submits) strictly follows; passes stay parallel (R/R).
    frame_cid: c.ke_component_id,
    begin_access: [2]c.ke_component_access, // WRITE backbuffer, WRITE frame
    clear_access: [2]c.ke_component_access, // WRITE backbuffer, READ frame
    end_access: [2]c.ke_component_access, // READ backbuffer, WRITE frame

    // Forward pass
    fwd_pipeline: c.ke_gpu_pipeline,
    fwd_obj_bind_group: c.ke_gpu_bind_group, // set 2, per-object (dynamic offset)
    fwd_obj_uniform: c.ke_gpu_buffer,
    fwd_frame_bind_group: c.ke_gpu_bind_group, // set 0, per-frame
    fwd_frame_uniform: c.ke_gpu_buffer,
    fwd_writes: [2][*c]const u8,
    fwd_reads: [1][*c]const u8,
    fwd_io: c.ke_render_pass_io,
    fwd_access: [13]c.ke_component_access,
    mesh_cid: c.ke_component_id,
    transform_cid: c.ke_component_id,
    camera_cid: c.ke_component_id,
    light_cid: c.ke_component_id,
    point_light_cid: c.ke_component_id,
    spot_light_cid: c.ke_component_id,
    ambient_cid: c.ke_component_id,
    skybox_cid: c.ke_component_id,

    // Skybox (drawn inside the forward pass: clear → meshes → skybox depth-LEQUAL)
    sky_pipeline: c.ke_gpu_pipeline,
    sky_vbo: c.ke_gpu_buffer,
    sky_ibo: c.ke_gpu_buffer,
    frame_bgl: c.ke_gpu_bind_group_layout, // set 0 layout (rebuild bind group on env change)
    env_cubemap: c.ke_texture_handle, // currently bound env (default until a skybox is set)
    shadow_view: c.ke_gpu_texture_view, // the shadow map's view (for set 0 binding)

    // Shadow-depth pass (renders casters from the light POV into shadow_map)
    shadow_pipeline: c.ke_gpu_pipeline,
    shadow_lvp_uniform: c.ke_gpu_buffer, // set 0: light view-proj
    shadow_lvp_bg: c.ke_gpu_bind_group,
    shadow_obj_uniform: c.ke_gpu_buffer, // set 1: per-object model (dynamic offset)
    shadow_obj_bg: c.ke_gpu_bind_group,
    shadow_writes: [2][*c]const u8,
    shadow_io: c.ke_render_pass_io,
    shadow_access: [6]c.ke_component_access,

    // Set 3 — clustered light lists (forward reads what the cull pass wrote).
    light_set_bgl: c.ke_gpu_bind_group_layout,
    fwd_light_bind_group: c.ke_gpu_bind_group,

    // Storage buffers shared by the cull pass (writes) and the forward (reads).
    point_lights_sb: c.ke_gpu_buffer,
    spot_lights_sb: c.ke_gpu_buffer,
    point_indices_sb: c.ke_gpu_buffer,
    point_counts_sb: c.ke_gpu_buffer,
    spot_indices_sb: c.ke_gpu_buffer,
    spot_counts_sb: c.ke_gpu_buffer,

    // Light cull compute pass.
    cull_pipeline: c.ke_gpu_pipeline,
    cull_uniform: c.ke_gpu_buffer,
    cull_bind_group: c.ke_gpu_bind_group,
    cull_io: c.ke_render_pass_io,
    cull_access: [6]c.ke_component_access,
    cull_queries: [3]c.ke_query_decl, // [point_light,transform], [spot_light,transform], [camera,transform]
    clusters_cid: c.ke_component_id, // tag: cull WRITES, forward READS (ordering)
};

// Per-object model for the shadow pass (set 1).
const ShadowObj = extern struct { model: [16]f32 };

// Mirrors the framework SkyboxComponent (registered under "Skybox"): a cubemap
// texture handle.
const SkyboxComp = extern struct { cubemap: c.ke_texture_handle };

inline fn stateOf(user: ?*anyopaque) *ModuleState {
    return @alignCast(@ptrCast(user.?));
}

// ── Projection helpers (consume the backend NDC convention) ──────────────────
// The view is always built left-handed (the engine owns the world convention).
// The projection absorbs the backend's clip-space quirks: the depth range
// (z[0,1] vs OpenGL z[-1,1]) and the Y flip (Vulkan's top-left framebuffer
// origin). A right-handed-clip backend is rejected at setup (it would need a
// right-handed world convention), so only the Lh family is used here.
fn makePerspective(ndc: c.ke_ndc_convention, fovy: f32, aspect: f32, near: f32, far: f32) zm.Mat {
    var p = if (ndc.z_zero_to_one != 0)
        zm.perspectiveFovLh(fovy, aspect, near, far)
    else
        zm.perspectiveFovLhGl(fovy, aspect, near, far);
    if (ndc.y_flip != 0) p[1][1] = -p[1][1];
    return p;
}

fn makeOrtho(ndc: c.ke_ndc_convention, w: f32, h: f32, near: f32, far: f32) zm.Mat {
    var p = if (ndc.z_zero_to_one != 0)
        zm.orthographicLh(w, h, near, far)
    else
        zm.orthographicLhGl(w, h, near, far);
    if (ndc.y_flip != 0) p[1][1] = -p[1][1];
    return p;
}

// ── Frame-boundary systems (ordered by the backbuffer tag-cid) ────────────────

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

// ── Shadow-depth pass ─────────────────────────────────────────────────────────
// Orthographic light view-proj; the light source sits opposite the travel
// direction. Matches the legacy bgfx ShadowRenderSystem (frustum 20, far 50).
fn lightViewProj(ndc: c.ke_ndc_convention, ldir_in: zm.Vec) zm.Mat {
    const ldir = zm.normalize3(ldir_in);
    const eye3 = ldir * zm.f32x4s(-25.0);
    const eye = zm.f32x4(eye3[0], eye3[1], eye3[2], 1.0);
    const up = if (@abs(ldir[1]) > 0.99) zm.f32x4(0, 0, 1, 0) else zm.f32x4(0, 1, 0, 0);
    const lview = zm.lookAtLh(eye, zm.f32x4(0, 0, 0, 1), up);
    const lproj = makeOrtho(ndc, 20.0, 20.0, 0.1, 50.0);
    return zm.mul(lview, lproj);
}

fn lightDirOf(ctx: ?*c.ke_system_ctx, st: *ModuleState) zm.Vec {
    var ents: [*c]c.ke_entity = undefined;
    var data: ?*anyopaque = undefined;
    var count: usize = 0;
    c.ke_system_ctx_query(ctx, st.light_cid, &ents, &data, &count);
    if (count == 0) return zm.f32x4(-0.4, -1.0, -0.3, 0.0);
    const dl: *const DirLight = @ptrCast(@alignCast(data));
    return zm.f32x4(dl.dir[0], dl.dir[1], dl.dir[2], 0.0);
}

// Left-handed view from a camera transform (identity rotation → look at origin;
// otherwise the world-matrix basis, looking down local −Z). Shared by the
// forward and the cull pass so both agree on view space.
fn cameraView(cam_tc: *const c.ke_transform_component) zm.Mat {
    const eye = zm.f32x4(cam_tc.position.x, cam_tc.position.y, cam_tc.position.z, 1.0);
    const q = cam_tc.rotation;
    if (@abs(q.x) < 1e-6 and @abs(q.y) < 1e-6 and @abs(q.z) < 1e-6)
        return zm.lookAtLh(eye, zm.f32x4(0, 0, 0, 1), zm.f32x4(0, 1, 0, 0));
    const m = cam_tc.world_matrix.m;
    const fwd = zm.f32x4(-m[8], -m[9], -m[10], 0);
    const up = zm.f32x4(m[4], m[5], m[6], 0);
    return zm.lookToLh(eye, fwd, up);
}

// ── Light cull compute pass ───────────────────────────────────────────────────
// Packs the scene's point + spot lights into storage buffers, then dispatches one
// thread per cluster to bin them. The forward reads the result; the "light_clusters"
// tag orders this pass before it.
fn cullSys(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    const core = st.core.ref;
    const deg2rad: f32 = std.math.pi / 180.0;
    // Pack point lights — view 0 = [point_light, transform], columns aligned.
    var pn: u32 = 0;
    {
        var segc: usize = 0;
        const segs = c.ke_system_ctx_view(ctx, 0, &segc);
        var s: usize = 0;
        while (s < segc) : (s += 1) {
            const pls: [*c]const PointLightComp = @ptrCast(@alignCast(segs[s].columns[0]));
            const tcs: [*c]const c.ke_transform_component = @ptrCast(@alignCast(segs[s].columns[1]));
            var i: usize = 0;
            while (i < segs[s].count and pn < MAX_LIGHTS) : (i += 1) {
                const m = tcs[i].world_matrix.m;
                const pg = PointLightGpu{
                    .pos_radius = .{ m[12], m[13], m[14], pls[i].radius },
                    .color_intensity = .{ pls[i].color[0], pls[i].color[1], pls[i].color[2], pls[i].intensity },
                };
                core.*.upload.?(core, st.point_lights_sb, pn * @sizeOf(PointLightGpu), &pg, @sizeOf(PointLightGpu));
                pn += 1;
            }
        }
    }

    // Pack spot lights — view 1 = [spot_light, transform]; cone cosines precomputed.
    var sn: u32 = 0;
    {
        var segc: usize = 0;
        const segs = c.ke_system_ctx_view(ctx, 1, &segc);
        var s: usize = 0;
        while (s < segc) : (s += 1) {
            const sls: [*c]const SpotLightComp = @ptrCast(@alignCast(segs[s].columns[0]));
            const tcs: [*c]const c.ke_transform_component = @ptrCast(@alignCast(segs[s].columns[1]));
            var i: usize = 0;
            while (i < segs[s].count and sn < MAX_LIGHTS) : (i += 1) {
                const m = tcs[i].world_matrix.m;
                const sg = SpotLightGpu{
                    .pos_range = .{ m[12], m[13], m[14], sls[i].range },
                    .dir_cos_inner = .{ sls[i].dir[0], sls[i].dir[1], sls[i].dir[2], std.math.cos(sls[i].inner_deg * deg2rad) },
                    .color_intensity = .{ sls[i].color[0], sls[i].color[1], sls[i].color[2], sls[i].intensity },
                    .cone = .{ std.math.cos(sls[i].outer_deg * deg2rad), 0.0, 0.0, 0.0 },
                };
                core.*.upload.?(core, st.spot_lights_sb, sn * @sizeOf(SpotLightGpu), &sg, @sizeOf(SpotLightGpu));
                sn += 1;
            }
        }
    }

    // Camera → view + projection params (must match the forward's). View 2 =
    // [camera, transform]; the first match is the active camera.
    var cam_segc: usize = 0;
    const cam_segs = c.ke_system_ctx_view(ctx, 2, &cam_segc);
    if (cam_segc == 0 or cam_segs[0].count == 0) return;
    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_segs[0].columns[0]));
    const cam_tc: *const c.ke_transform_component = @ptrCast(@alignCast(cam_segs[0].columns[1]));

    const pc = core.*.begin_pass.?(core, ctx, &st.cull_io);
    if (pc == null) return;
    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    var params: ClusterParams = .{
        .grid = .{ GRID_X, GRID_Y, GRID_Z, MAX_LIGHTS_PER_CLUSTER },
        .counts = .{ @floatFromInt(pn), @floatFromInt(sn), 0.0, 0.0 },
        .proj = .{ std.math.tan(cam.fov * deg2rad * 0.5), aspect, cam.near_plane, cam.far_plane },
        .view = undefined,
    };
    zm.storeMat(params.view[0..], cameraView(cam_tc));
    core.*.upload.?(core, st.cull_uniform, 0, &params, @sizeOf(ClusterParams));

    const cp = pc.*.begin_compute.?(pc);
    cp.*.set_pipeline.?(cp, st.cull_pipeline);
    cp.*.set_bind_group.?(cp, 0, st.cull_bind_group, null, 0);
    cp.*.dispatch.?(cp, (NUM_CLUSTERS + 63) / 64, 1, 1);
    cp.*.end.?(cp);
    core.*.end_pass.?(core, pc);
}

fn shadowSys(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    const core = st.core.ref;

    const lvp = lightViewProj(st.ndc, lightDirOf(ctx, st));
    var lvp_arr: [16]f32 = undefined;
    zm.storeMat(lvp_arr[0..], lvp);
    core.*.upload.?(core, st.shadow_lvp_uniform, 0, &lvp_arr, 64);

    const pc = core.*.begin_pass.?(core, ctx, &st.shadow_io);
    if (pc == null) return;

    var ents: [*c]c.ke_entity = undefined;
    var data: ?*anyopaque = undefined;
    var count: usize = 0;
    c.ke_system_ctx_query(ctx, st.mesh_cid, &ents, &data, &count);
    const meshes: [*c]const c.ke_mesh_component = @ptrCast(@alignCast(data));
    const n: u32 = @intCast(@min(count, MAX_DRAWS));

    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const tc_raw = c.ke_system_ctx_get(ctx, st.transform_cid, ents[i]) orelse continue;
        const tc: *const c.ke_transform_component = @ptrCast(@alignCast(tc_raw));
        var u: ShadowObj = undefined;
        @memcpy(u.model[0..], tc.world_matrix.m[0..16]);
        core.*.upload.?(core, st.shadow_obj_uniform, i * UNIFORM_STRIDE, &u, @sizeOf(ShadowObj));
    }

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, st.shadow_pipeline);
    rp.*.set_bind_group.?(rp, 0, st.shadow_lvp_bg, null, 0);
    i = 0;
    while (i < n) : (i += 1) {
        var vbo: c.ke_gpu_buffer = 0;
        var ibo: c.ke_gpu_buffer = 0;
        var idx_count: u32 = 0;
        if (core.*.mesh_buffers.?(core, meshes[i].mesh, &vbo, &ibo, &idx_count) == 0) continue;
        const offset: u32 = i * UNIFORM_STRIDE;
        rp.*.set_bind_group.?(rp, 1, st.shadow_obj_bg, &offset, 1);
        rp.*.set_vertex_buffer.?(rp, 0, vbo, 0);
        rp.*.set_index_buffer.?(rp, ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.*.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
    }
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

// ── Forward mesh pass ─────────────────────────────────────────────────────────

fn forwardSys(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    const core = st.core.ref;

    // Camera: take the first camera entity + its transform.
    var cam_ents: [*c]c.ke_entity = undefined;
    var cam_data: ?*anyopaque = undefined;
    var cam_count: usize = 0;
    c.ke_system_ctx_query(ctx, st.camera_cid, &cam_ents, &cam_data, &cam_count);
    if (cam_count == 0) return;
    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_data));
    const cam_tc_raw = c.ke_system_ctx_get(ctx, st.transform_cid, cam_ents[0]) orelse return;
    const cam_tc: *const c.ke_transform_component = @ptrCast(@alignCast(cam_tc_raw));

    const pc = core.*.begin_pass.?(core, ctx, &st.fwd_io);
    if (pc == null) return;

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    const view = cameraView(cam_tc);
    // ke_camera_component.fov is in degrees (the cross-backend convention).
    const fov_rad = cam.fov * @as(f32, std.math.pi / 180.0);
    const proj = makePerspective(st.ndc, fov_rad, aspect, cam.near_plane, cam.far_plane);
    const view_proj = zm.mul(view, proj);

    // Skybox view: rotation-only (translation zeroed) × proj, so the cube stays
    // centred on the camera (infinite background).
    var vm: [16]f32 = undefined;
    zm.storeMat(vm[0..], view);
    vm[12] = 0;
    vm[13] = 0;
    vm[14] = 0;
    const sky_vp = zm.mul(zm.loadMat(vm[0..]), proj);

    // Environment cubemap from the first skybox entity (default black otherwise);
    // rebuild set 0 only when the bound environment changes.
    var sky_ents: [*c]c.ke_entity = undefined;
    var sky_data: ?*anyopaque = undefined;
    var sky_count: usize = 0;
    c.ke_system_ctx_query(ctx, st.skybox_cid, &sky_ents, &sky_data, &sky_count);
    const want_env: c.ke_texture_handle = if (sky_count != 0)
        (@as(*const SkyboxComp, @ptrCast(@alignCast(sky_data)))).cubemap
    else
        .{ .idx = c.KE_HANDLE_NONE };
    if (want_env.idx != st.env_cubemap.idx) {
        st.env_cubemap = want_env;
        rebuildFrameBindGroup(st);
    }

    // Per-frame: camera + lights. All light terms default off; each present light
    // turns on its contribution (a scene with only point lights has no directional).
    var frame: PerFrame = .{
        .camera_pos = .{ cam_tc.position.x, cam_tc.position.y, cam_tc.position.z, 1.0 },
        .light_dir = .{ -0.4, -1.0, -0.3, 0.0 },
        .light_color = .{ 1.0, 1.0, 1.0, 1.0 },
        .ambient = .{ 0.0, 0.0, 0.0, 0.0 },
        .sky_view_proj = undefined,
        .light_vp = undefined,
        .shadow_params = .{ 0.0, 0.0, 0.0, 0.0 }, // x=shadow active, z=directional active
        .view = undefined,
        .cluster_grid = .{ GRID_X, GRID_Y, GRID_Z, MAX_LIGHTS_PER_CLUSTER },
        .cluster_viewport = .{ @floatFromInt(bw), @floatFromInt(bh), cam.near_plane, cam.far_plane },
    };
    zm.storeMat(frame.sky_view_proj[0..], sky_vp);
    zm.storeMat(frame.view[0..], view); // for the fragment's cluster z slice
    // Same light view-proj the shadow pass used, for the forward's shadow lookup.
    zm.storeMat(frame.light_vp[0..], lightViewProj(st.ndc, lightDirOf(ctx, st)));

    // Directional light (first entity). Present → enable the directional term +
    // its shadow map; its ambient seeds the scene ambient. Point/spot lights are
    // accumulated from the clustered storage buffers (the cull pass binned them).
    var li_ents: [*c]c.ke_entity = undefined;
    var li_data: ?*anyopaque = undefined;
    var li_count: usize = 0;
    c.ke_system_ctx_query(ctx, st.light_cid, &li_ents, &li_data, &li_count);
    if (li_count != 0) {
        const dl: *const DirLight = @ptrCast(@alignCast(li_data));
        frame.light_dir = .{ dl.dir[0], dl.dir[1], dl.dir[2], 0.0 };
        frame.light_color = .{ dl.rgb[0], dl.rgb[1], dl.rgb[2], dl.intensity };
        frame.ambient = .{ dl.ambient[0], dl.ambient[1], dl.ambient[2], 0.0 };
        frame.shadow_params[0] = 1.0; // shadow active
        frame.shadow_params[2] = 1.0; // directional active
    }

    // Standalone ambient light (overrides the directional's ambient when present).
    var am_ents: [*c]c.ke_entity = undefined;
    var am_data: ?*anyopaque = undefined;
    var am_count: usize = 0;
    c.ke_system_ctx_query(ctx, st.ambient_cid, &am_ents, &am_data, &am_count);
    if (am_count != 0) {
        const al: *const AmbientComp = @ptrCast(@alignCast(am_data));
        frame.ambient = .{ al.color[0], al.color[1], al.color[2], 0.0 };
    }

    core.*.upload.?(core, st.fwd_frame_uniform, 0, &frame, @sizeOf(PerFrame));

    // Meshes: build + upload one uniform region per draw (queue writes land before
    // the recorded draws, so each dynamic offset reads its own object).
    var ents: [*c]c.ke_entity = undefined;
    var data: ?*anyopaque = undefined;
    var count: usize = 0;
    c.ke_system_ctx_query(ctx, st.mesh_cid, &ents, &data, &count);
    const meshes: [*c]const c.ke_mesh_component = @ptrCast(@alignCast(data));
    const n: u32 = @intCast(@min(count, MAX_DRAWS));

    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const tc_raw = c.ke_system_ctx_get(ctx, st.transform_cid, ents[i]) orelse continue;
        const tc: *const c.ke_transform_component = @ptrCast(@alignCast(tc_raw));
        const model = zm.loadMat(tc.world_matrix.m[0..]);
        const mvp = zm.mul(model, view_proj);

        var u: PerObject = undefined;
        zm.storeMat(u.mvp[0..], mvp);
        zm.storeMat(u.model[0..], model);
        core.*.upload.?(core, st.fwd_obj_uniform, i * UNIFORM_STRIDE, &u, @sizeOf(PerObject));
    }

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, st.fwd_pipeline);
    rp.*.set_bind_group.?(rp, 0, st.fwd_frame_bind_group, null, 0); // set 0: per-frame
    rp.*.set_bind_group.?(rp, 3, st.fwd_light_bind_group, null, 0); // set 3: clustered lights
    i = 0;
    while (i < n) : (i += 1) {
        var vbo: c.ke_gpu_buffer = 0;
        var ibo: c.ke_gpu_buffer = 0;
        var idx_count: u32 = 0;
        if (core.*.mesh_buffers.?(core, meshes[i].mesh, &vbo, &ibo, &idx_count) == 0) continue;
        const offset: u32 = i * UNIFORM_STRIDE;
        const mat_bg = core.*.material_bind_group.?(core, meshes[i].material);
        rp.*.set_bind_group.?(rp, 1, mat_bg, null, 0); // set 1: per-material
        rp.*.set_bind_group.?(rp, 2, st.fwd_obj_bind_group, &offset, 1); // set 2: per-object
        rp.*.set_vertex_buffer.?(rp, 0, vbo, 0);
        rp.*.set_index_buffer.?(rp, ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.*.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
    }

    // Skybox last — depth LEQUAL, no depth write: fills only the background pixels
    // the opaque meshes did not cover, within the same render pass (no load-op).
    rp.*.set_pipeline.?(rp, st.sky_pipeline);
    rp.*.set_bind_group.?(rp, 0, st.fwd_frame_bind_group, null, 0);
    rp.*.set_vertex_buffer.?(rp, 0, st.sky_vbo, 0);
    rp.*.set_index_buffer.?(rp, st.sky_ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
    rp.*.draw_indexed.?(rp, sky_idx.len, 1, 0, 0, 0);

    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

// Builds set 0 (per-frame uniform + env cubemap + sampler). Called at setup and
// whenever the bound environment cubemap changes (rare — at scene load).
fn rebuildFrameBindGroup(st: *ModuleState) void {
    const dev = st.device;
    const core = st.core.ref;
    const env_view = core.*.texture_view.?(core, st.env_cubemap);
    const smp = core.*.sampler.?(core);
    const entries = [_]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = st.fwd_frame_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(PerFrame), .texture_view = 0, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = env_view, .sampler = 0 },
        .{ .binding = 2, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
        .{ .binding = 3, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = st.shadow_view, .sampler = 0 },
    };
    st.fwd_frame_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = st.frame_bgl,
        .entry_count = 4,
        .entries = &entries,
    });
}

fn forwardSetup(st: *ModuleState, e: *c.ke_ecs, out_error: [*c][*c]c.ke_error) bool {
    const dev = st.device;

    // Clip-space convention of the active backend. The view stays left-handed
    // (the engine's world convention); makePerspective/makeOrtho absorb the z
    // range + Y flip. A right-handed-clip backend would require a right-handed
    // world convention — reject it loudly rather than rendering mirrored.
    st.ndc = dev.get_ndc_convention.?(dev);
    if (st.ndc.left_handed == 0) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "render: right-handed clip-space backend not supported (engine world convention is left-handed)", @src().file, @intCast(@src().line), null);
        return false;
    }

    st.mesh_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_MESH, @sizeOf(c.ke_mesh_component));
    st.transform_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_TRANSFORM, @sizeOf(c.ke_transform_component));
    st.camera_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_CAMERA, @sizeOf(c.ke_camera_component));
    st.light_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, @sizeOf(c.ke_directional_light_component));
    st.point_light_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_POINT_LIGHT, @sizeOf(PointLightComp));
    st.spot_light_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_SPOT_LIGHT, @sizeOf(SpotLightComp));
    st.ambient_cid = e.component_register.?(e, "AmbientLight", @sizeOf(AmbientComp));
    st.skybox_cid = e.component_register.?(e, "Skybox", @sizeOf(SkyboxComp));
    st.env_cubemap = .{ .idx = c.KE_HANDLE_NONE }; // default (black) cube until a skybox is set

    const vs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(forward_vs_wgsl),
        .byte_size = forward_vs_wgsl.len,
        .entry_point = "forward.vs",
    }, out_error);
    if (vs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, vs);

    const fs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(forward_fs_wgsl),
        .byte_size = forward_fs_wgsl.len,
        .entry_point = "forward.fs",
    }, out_error);
    if (fs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, fs);

    // Set 2 — per-object transform (dynamic offset, vertex stage).
    const obj_bgl_entry = c.ke_gpu_bind_group_layout_entry{
        .binding = 0,
        .visibility = c.KE_GPU_SHADER_STAGE_VERTEX,
        .type = c.KE_GPU_BINDING_TYPE_BUFFER,
        .has_dynamic_offset = 1,
        .view_dimension = 0,
    };
    const obj_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 1,
        .entries = &obj_bgl_entry,
    });

    // Set 0 — per-frame uniform (vs reads sky_view_proj; fs reads camera/light) +
    // environment cubemap + sampler (fs, for skybox + IBL).
    const frame_bgl_entries = [_]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 1, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = c.KE_GPU_TEXTURE_DIM_CUBE },
        .{ .binding = 2, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 3, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 }, // shadow map (2D R32F)
    };
    const frame_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 4,
        .entries = &frame_bgl_entries,
    });
    st.frame_bgl = frame_bgl;

    const attrs = [_]c.ke_gpu_vertex_attribute{
        .{ .shader_location = 0, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 },
        .{ .shader_location = 1, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 3 * @sizeOf(f32) },
        .{ .shader_location = 2, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = 6 * @sizeOf(f32) },
        .{ .shader_location = 3, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 8 * @sizeOf(f32) },
    };
    const vbl = c.ke_gpu_vertex_buffer_layout{
        .stride = 11 * @sizeOf(f32),
        .step_mode = c.KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 4,
        .attributes = &attrs,
    };
    var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    pp.vertex_module = vs;
    pp.fragment_module = fs;
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = c.KE_GPU_CULL_MODE_NONE; // winding-agnostic for the first pass; depth sorts
    pp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    pp.vertex_buffer_count = 1;
    pp.vertex_buffers = &vbl;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = 1;
    pp.depth_stencil.depth_write_enabled = 1;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_LESS;
    // Clustered light culling: storage buffers + cull compute pipeline + the
    // forward's set-3 light bind group (the layout is needed for this pipeline).
    if (!clusterSetup(st, e, out_error)) return false;
    pp.bind_group_layouts[0] = frame_bgl; // set 0: per-frame (camera + light)
    pp.bind_group_layouts[1] = st.core.ref.*.material_layout.?(st.core.ref); // set 1: per-material
    pp.bind_group_layouts[2] = obj_bgl; // set 2: per-object (transform)
    pp.bind_group_layouts[3] = st.light_set_bgl; // set 3: clustered light lists
    pp.bind_group_layout_count = 4;
    pp.color_target_format = 0; // swapchain
    st.fwd_pipeline = dev.create_render_pipeline.?(dev, &pp);
    if (st.fwd_pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "forward pass: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    // Set 2 — per-object ring (one dynamic-offset region per draw).
    st.fwd_obj_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = UNIFORM_STRIDE * MAX_DRAWS,
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    });
    const obj_bg_entry = c.ke_gpu_bind_group_entry{
        .binding = 0,
        .type = c.KE_GPU_BINDING_TYPE_BUFFER,
        .buffer = st.fwd_obj_uniform,
        .buffer_offset = 0,
        .buffer_size = @sizeOf(PerObject),
        .texture_view = 0,
        .sampler = 0,
    };
    st.fwd_obj_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = obj_bgl,
        .entry_count = 1,
        .entries = &obj_bg_entry,
    });

    // ── Shadow-depth pass: targets + pipeline + uniforms ──────────────────
    const shadow_map_cid = st.core.ref.*.declare.?(st.core.ref, &c.ke_render_resource_desc{
        .name = "shadow_map",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT, // filterable; depth in .r
        .size_mode = c.KE_RENDER_SIZE_ABSOLUTE,
        .width = SHADOW_RES,
        .height = SHADOW_RES,
        .scale_x = 1.0,
        .scale_y = 1.0,
    }, null);
    const shadow_depth_cid = st.core.ref.*.declare.?(st.core.ref, &c.ke_render_resource_desc{
        .name = "shadow_depth",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_ABSOLUTE,
        .width = SHADOW_RES,
        .height = SHADOW_RES,
        .scale_x = 1.0,
        .scale_y = 1.0,
    }, null);
    st.shadow_view = st.core.ref.*.resource_view.?(st.core.ref, "shadow_map");

    const sh_vs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{ .code = @ptrCast(shadow_vs_wgsl), .byte_size = shadow_vs_wgsl.len, .entry_point = "shadow.vs" }, out_error);
    if (sh_vs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, sh_vs);
    const sh_fs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{ .code = @ptrCast(shadow_fs_wgsl), .byte_size = shadow_fs_wgsl.len, .entry_point = "shadow.fs" }, out_error);
    if (sh_fs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, sh_fs);

    const sh_lvp_entry = c.ke_gpu_bind_group_layout_entry{ .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_VERTEX, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 };
    const sh_lvp_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{ .entry_count = 1, .entries = &sh_lvp_entry });
    const sh_obj_entry = c.ke_gpu_bind_group_layout_entry{ .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_VERTEX, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 1, .view_dimension = 0 };
    const sh_obj_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{ .entry_count = 1, .entries = &sh_obj_entry });

    const sh_attr = c.ke_gpu_vertex_attribute{ .shader_location = 0, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 };
    const sh_vbl = c.ke_gpu_vertex_buffer_layout{ .stride = 11 * @sizeOf(f32), .step_mode = c.KE_GPU_VERTEX_STEP_MODE_VERTEX, .attribute_count = 1, .attributes = &sh_attr };
    var shp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    shp.vertex_module = sh_vs;
    shp.fragment_module = sh_fs;
    shp.vertex_entry = "vs_main";
    shp.fragment_entry = "fs_main";
    shp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    shp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    shp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    shp.vertex_buffer_count = 1;
    shp.vertex_buffers = &sh_vbl;
    shp.blend_state.write_mask = 0x0F;
    shp.depth_stencil.depth_test_enabled = 1;
    shp.depth_stencil.depth_write_enabled = 1;
    shp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_LESS;
    shp.bind_group_layouts[0] = sh_lvp_bgl;
    shp.bind_group_layouts[1] = sh_obj_bgl;
    shp.bind_group_layout_count = 2;
    shp.color_target_format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
    st.shadow_pipeline = dev.create_render_pipeline.?(dev, &shp);
    if (st.shadow_pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "shadow pass: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    st.shadow_lvp_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{ .initial_data = null, .size = 64, .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST, .mapped_at_creation = 0 });
    const sh_lvp_bg_entry = c.ke_gpu_bind_group_entry{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = st.shadow_lvp_uniform, .buffer_offset = 0, .buffer_size = 64, .texture_view = 0, .sampler = 0 };
    st.shadow_lvp_bg = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{ .layout = sh_lvp_bgl, .entry_count = 1, .entries = &sh_lvp_bg_entry });

    st.shadow_obj_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{ .initial_data = null, .size = UNIFORM_STRIDE * MAX_DRAWS, .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST, .mapped_at_creation = 0 });
    const sh_obj_bg_entry = c.ke_gpu_bind_group_entry{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = st.shadow_obj_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(ShadowObj), .texture_view = 0, .sampler = 0 };
    st.shadow_obj_bg = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{ .layout = sh_obj_bgl, .entry_count = 1, .entries = &sh_obj_bg_entry });

    st.shadow_writes = .{ "shadow_map", "shadow_depth" };
    st.shadow_io = std.mem.zeroes(c.ke_render_pass_io);
    st.shadow_io.writes = @ptrCast(&st.shadow_writes);
    st.shadow_io.writes_count = 2;
    st.shadow_io.cmd_slot = 1; // shadow pass → frame command slot 1 (before forward)
    st.shadow_access = .{
        .{ .cid = shadow_map_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = shadow_depth_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = st.mesh_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.frame_cid, .access = c.KE_ACCESS_READ },
    };

    // Set 0 — per-frame uniform + env cubemap + sampler + shadow map. The bind
    // group is rebuilt (rebuildFrameBindGroup) when the bound environment changes.
    st.fwd_frame_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = @sizeOf(PerFrame),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    });
    rebuildFrameBindGroup(st);

    // Skybox pipeline (set 0 only): position-only cube, depth LEQUAL, no write.
    const sky_vs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(skybox_vs_wgsl),
        .byte_size = skybox_vs_wgsl.len,
        .entry_point = "skybox.vs",
    }, out_error);
    if (sky_vs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, sky_vs);
    const sky_fs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(skybox_fs_wgsl),
        .byte_size = skybox_fs_wgsl.len,
        .entry_point = "skybox.fs",
    }, out_error);
    if (sky_fs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, sky_fs);

    const sky_attr = c.ke_gpu_vertex_attribute{ .shader_location = 0, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 };
    const sky_vbl = c.ke_gpu_vertex_buffer_layout{
        .stride = 3 * @sizeOf(f32),
        .step_mode = c.KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 1,
        .attributes = &sky_attr,
    };
    var skp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    skp.vertex_module = sky_vs;
    skp.fragment_module = sky_fs;
    skp.vertex_entry = "vs_main";
    skp.fragment_entry = "fs_main";
    skp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    skp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    skp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    skp.vertex_buffer_count = 1;
    skp.vertex_buffers = &sky_vbl;
    skp.blend_state.write_mask = 0x0F;
    skp.depth_stencil.depth_test_enabled = 1;
    skp.depth_stencil.depth_write_enabled = 0; // skybox never occludes
    skp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_LESS_EQUAL;
    skp.bind_group_layouts[0] = frame_bgl;
    skp.bind_group_layout_count = 1;
    skp.color_target_format = 0;
    st.sky_pipeline = dev.create_render_pipeline.?(dev, &skp);
    if (st.sky_pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "skybox: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }
    st.sky_vbo = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = &sky_verts,
        .size = @sizeOf(@TypeOf(sky_verts)),
        .usage = c.KE_GPU_BUFFER_USAGE_VERTEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    });
    st.sky_ibo = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = &sky_idx,
        .size = @sizeOf(@TypeOf(sky_idx)),
        .usage = c.KE_GPU_BUFFER_USAGE_INDEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    });

    // Transient depth target, sized to the backbuffer (the core resolves the
    // scale against its current swapchain size).
    const depth_cid = st.core.ref.*.declare.?(st.core.ref, &c.ke_render_resource_desc{
        .name = "depth",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0,
        .height = 0,
        .scale_x = 1.0,
        .scale_y = 1.0,
    }, null);

    st.fwd_writes = .{ "backbuffer", "depth" };
    st.fwd_reads = .{"shadow_map"};
    st.fwd_io = std.mem.zeroes(c.ke_render_pass_io);
    st.fwd_io.writes = @ptrCast(&st.fwd_writes);
    st.fwd_io.writes_count = 2;
    st.fwd_io.reads = @ptrCast(&st.fwd_reads);
    st.fwd_io.reads_count = 1;
    st.fwd_io.cmd_slot = 3; // forward pass → frame command slot 3 (after cull)

    const bb_cid = st.core.ref.*.cid.?(st.core.ref, "backbuffer");
    st.fwd_access = .{
        .{ .cid = bb_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = depth_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = st.mesh_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.camera_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.skybox_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.core.ref.*.cid.?(st.core.ref, "shadow_map"), .access = c.KE_ACCESS_READ },
        .{ .cid = st.frame_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.point_light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.spot_light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.ambient_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.clusters_cid, .access = c.KE_ACCESS_READ }, // after the cull pass
    };
    return true;
}

fn makeStorageBuffer(dev: *c.ke_gpu_device, size: usize) c.ke_gpu_buffer {
    return dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = size,
        .usage = c.KE_GPU_BUFFER_USAGE_STORAGE | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    });
}

// Storage buffers + the cull compute pipeline + the forward's set-3 light bind
// group. The cull pass writes the per-cluster index lists; the forward reads them.
fn clusterSetup(st: *ModuleState, e: *c.ke_ecs, out_error: [*c][*c]c.ke_error) bool {
    const dev = st.device;

    const point_lights_bytes = MAX_LIGHTS * @sizeOf(PointLightGpu);
    const spot_lights_bytes = MAX_LIGHTS * @sizeOf(SpotLightGpu);
    const indices_bytes = NUM_CLUSTERS * MAX_LIGHTS_PER_CLUSTER * @sizeOf(u32);
    const counts_bytes = NUM_CLUSTERS * @sizeOf(u32);

    st.point_lights_sb = makeStorageBuffer(dev, point_lights_bytes);
    st.spot_lights_sb = makeStorageBuffer(dev, spot_lights_bytes);
    st.point_indices_sb = makeStorageBuffer(dev, indices_bytes);
    st.point_counts_sb = makeStorageBuffer(dev, counts_bytes);
    st.spot_indices_sb = makeStorageBuffer(dev, indices_bytes);
    st.spot_counts_sb = makeStorageBuffer(dev, counts_bytes);

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
    };
    st.light_set_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 6,
        .entries = &light_bgl_entries,
    });
    const light_bg_entries = [_]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = ro, .buffer = st.point_lights_sb, .buffer_offset = 0, .buffer_size = point_lights_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 1, .type = ro, .buffer = st.spot_lights_sb, .buffer_offset = 0, .buffer_size = spot_lights_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 2, .type = ro, .buffer = st.point_indices_sb, .buffer_offset = 0, .buffer_size = indices_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 3, .type = ro, .buffer = st.point_counts_sb, .buffer_offset = 0, .buffer_size = counts_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 4, .type = ro, .buffer = st.spot_indices_sb, .buffer_offset = 0, .buffer_size = indices_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 5, .type = ro, .buffer = st.spot_counts_sb, .buffer_offset = 0, .buffer_size = counts_bytes, .texture_view = 0, .sampler = 0 },
    };
    st.fwd_light_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = st.light_set_bgl,
        .entry_count = 6,
        .entries = &light_bg_entries,
    });

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

    st.cull_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = @sizeOf(ClusterParams),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    });
    const cull_bg_entries = [_]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = st.cull_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(ClusterParams), .texture_view = 0, .sampler = 0 },
        .{ .binding = 1, .type = ro, .buffer = st.point_lights_sb, .buffer_offset = 0, .buffer_size = point_lights_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 2, .type = ro, .buffer = st.spot_lights_sb, .buffer_offset = 0, .buffer_size = spot_lights_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 3, .type = rw, .buffer = st.point_indices_sb, .buffer_offset = 0, .buffer_size = indices_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 4, .type = rw, .buffer = st.point_counts_sb, .buffer_offset = 0, .buffer_size = counts_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 5, .type = rw, .buffer = st.spot_indices_sb, .buffer_offset = 0, .buffer_size = indices_bytes, .texture_view = 0, .sampler = 0 },
        .{ .binding = 6, .type = rw, .buffer = st.spot_counts_sb, .buffer_offset = 0, .buffer_size = counts_bytes, .texture_view = 0, .sampler = 0 },
    };
    st.cull_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = cull_bgl,
        .entry_count = 7,
        .entries = &cull_bg_entries,
    });

    const cs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(cluster_cull_cs_wgsl),
        .byte_size = cluster_cull_cs_wgsl.len,
        .entry_point = "cluster.cs",
    }, out_error);
    if (cs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, cs);

    const cull_layouts = [_]c.ke_gpu_bind_group_layout{ cull_bgl, 0, 0, 0 };
    st.cull_pipeline = dev.create_compute_pipeline.?(dev, &c.ke_gpu_compute_pipeline_params{
        .compute_module = cs,
        .compute_entry = "cs_main",
        .bind_group_layouts = cull_layouts,
        .bind_group_layout_count = 1,
    });
    if (st.cull_pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "cull pass: compute pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    // Ordering tag: the cull pass WRITES it, the forward READS it (cull → forward).
    st.clusters_cid = e.component_register.?(e, "light_clusters", 0);
    st.cull_io = std.mem.zeroes(c.ke_render_pass_io);
    st.cull_io.cmd_slot = 2; // cull → frame command slot 2 (before forward)
    // The cull WRITES light_clusters and the forward READS it (cull → forward) —
    // the only ordering the cull needs. It may share a wave with the clear/shadow
    // render passes: the render core accumulates this compute pass's recording into
    // a CPU command list and replays it single-threaded at end_frame, so the unsafe
    // compute∥render recording never actually happens concurrently.
    st.cull_access = .{
        .{ .cid = st.clusters_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = st.point_light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.spot_light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.camera_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.frame_cid, .access = c.KE_ACCESS_READ },
    };

    // Data the cull body reads through resolved views: each light kind paired with
    // its transform, and the camera paired with its transform. Index order here is
    // the query_index the body passes to ke_system_ctx_view.
    const rd = c.KE_ACCESS_READ;
    st.cull_queries = std.mem.zeroes([3]c.ke_query_decl);
    st.cull_queries[0].terms[0] = .{ .cid = st.point_light_cid, .access = rd };
    st.cull_queries[0].terms[1] = .{ .cid = st.transform_cid, .access = rd };
    st.cull_queries[0].term_count = 2;
    st.cull_queries[1].terms[0] = .{ .cid = st.spot_light_cid, .access = rd };
    st.cull_queries[1].terms[1] = .{ .cid = st.transform_cid, .access = rd };
    st.cull_queries[1].term_count = 2;
    st.cull_queries[2].terms[0] = .{ .cid = st.camera_cid, .access = rd };
    st.cull_queries[2].terms[1] = .{ .cid = st.transform_cid, .access = rd };
    st.cull_queries[2].term_count = 2;
    return true;
}

fn registerSys(rt: *c.ke_runtime, name: [*c]const u8,
               queries: [*c]const c.ke_query_decl, query_count: u32,
               access: [*c]const c.ke_component_access, access_count: u32,
               user: *ModuleState, exec: ExecFn) void {
    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = name;
    params.phase = c.KE_PHASE_RENDER;
    params.queries = queries;
    params.query_count = query_count;
    params.access_list = access;
    params.access_count = access_count;
    params.pinned_thread = 0; // render systems run in parallel (sim ‖ render + parallel passes)
    params.user_data = user;
    params.execute = exec;
    _ = rt.register_system.?(rt, &params, null);
}

export fn ke_render_module_core(module: ?*c.ke_render_module) callconv(.c) ?*c.ke_render_core {
    const st: *ModuleState = @alignCast(@ptrCast(module orelse return null));
    return st.core.ref;
}

fn destroyModule(self: ?*c.ke_render_module) callconv(.c) void {
    const st: *ModuleState = @alignCast(@ptrCast(self orelse return));
    if (st.core.destroy) |d| d(st.core.ref);
    gpa.destroy(st);
}

const empty = c.ke_render_module_handle{ .ref = null, .destroy = null };

export fn ke_render_module_create(runtime: ?*c.ke_runtime, ecs: ?*c.ke_ecs, device: ?*c.ke_gpu_device,
                                  default_passes: c.ke_bool, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_module_handle {
    const rt = runtime orelse return empty;
    const e = ecs orelse return empty;
    const dev = device orelse return empty;

    const core_h = c.ke_render_core_create(dev, e, out_error);
    if (core_h.ref == null) return empty;

    const st = gpa.create(ModuleState) catch {
        if (core_h.destroy) |d| d(core_h.ref);
        return empty;
    };
    st.core = core_h;
    st.device = dev;
    st.bb_writes = .{"backbuffer"};
    st.io = std.mem.zeroes(c.ke_render_pass_io);
    st.io.writes = @ptrCast(&st.bb_writes);
    st.io.writes_count = 1;
    st.io.cmd_slot = 0; // clear pass → frame command slot 0

    const bb_cid = core_h.ref.*.cid.?(core_h.ref, "backbuffer");
    // Zero-size tag for the frame barrier (see ModuleState.frame_cid).
    st.frame_cid = e.component_register.?(e, "render.frame", 0);
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

    // No pass is imposed. default_passes registers the conventional chain;
    // otherwise the game wires its own passes. A failed setup (e.g. a bad shader)
    // fails loudly via out_error — it is never silently skipped.
    if (default_passes != 0) {
        if (!forwardSetup(st, e, out_error)) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }
        registerSys(rt, "render.begin_frame", null, 0, &st.begin_access, st.begin_access.len, st, beginFrameSys);
        registerSys(rt, "render.clear", null, 0, &st.clear_access, st.clear_access.len, st, clearSys);
        registerSys(rt, "render.shadow", null, 0, &st.shadow_access, st.shadow_access.len, st, shadowSys);
        registerSys(rt, "render.cull", &st.cull_queries, 3, &st.cull_access, st.cull_access.len, st, cullSys);
        registerSys(rt, "render.forward", null, 0, &st.fwd_access, st.fwd_access.len, st, forwardSys);
        registerSys(rt, "render.end_frame", null, 0, &st.end_access, st.end_access.len, st, endFrameSys);
    }

    return .{ .ref = @ptrCast(st), .destroy = destroyModule };
}
