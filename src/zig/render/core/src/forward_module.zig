const std = @import("std");
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;
const shadow_module = @import("shadow_module.zig");
const ShadowModule = shadow_module.ShadowModule;
const cluster_module = @import("cluster_module.zig");
const ClusterModule = cluster_module.ClusterModule;
const skybox_module = @import("skybox_module.zig");
const SkyboxModule = skybox_module.SkyboxModule;

// Forward+ mesh pass — the opaque-shading half of the deferred+forward end-state.
// It is the *consumer*: shadow, cluster (light cull), and skybox are their own
// modules set up before this one; forward borrows their handles (the shadow map
// + lvp uniform into set 0, the clustered light lists into set 3, the skybox
// draw folded into its render pass) rather than owning or wiring them. That is
// the honest coupling of a forward shading pass — it reads every feature's
// output to compute the final lit pixel — expressed as borrowed pointers, not a
// parent module reaching across a shared state blob.

const mat_test_flat_vs_wgsl = @embedFile("mat_test_flat.vs.wgsl");
const mat_test_flat_fs_wgsl = @embedFile("mat_test_flat.fs.wgsl");
const magenta_vs_wgsl = @embedFile("magenta.vs.wgsl");
const magenta_fs_wgsl = @embedFile("magenta.fs.wgsl");

const MAX_DRAWS = 512;
const UNIFORM_STRIDE = 256; // dynamic-offset alignment (>= minUniformBufferOffsetAlignment)

// Set 2 — per-object transform. Matches forward.slang PerObject.
const PerObject = extern struct {
    mvp: [16]f32,
    model: [16]f32,
};

// Set 0 — per-frame camera + light + skybox view. Matches forward.slang PerFrame.
const PerFrame = extern struct {
    camera_pos: [4]f32,
    light_dir: [4]f32,
    light_color: [4]f32, // rgb, w = intensity
    ambient: [4]f32,
    sky_view_proj: [16]f32, // rotation-only view*proj for the skybox
    shadow_params: [4]f32, // x = shadow active (vestigial), z = directional active
    view: [16]f32, // world→view (for the fragment's cluster z slice)
};

// Mirrors ke_directional_light_component (10 floats, see render/components.h).
const DirLight = extern struct {
    dir: [3]f32,
    rgb: [3]f32,
    intensity: f32,
    ambient: [3]f32,
};

// Mirrors the C# AmbientLightComponent { Vector3 Color } (registered "AmbientLight").
// Exported: the aggregator registers the component (its cid feeds forward's own
// access list), so it needs this struct's size at registration.
pub const AmbientComp = extern struct { color: [3]f32 };

// Mirrors the framework SkyboxComponent (registered under "Skybox"): a cubemap handle.
pub const SkyboxComp = extern struct { cubemap: c.ke_texture_handle };

pub const ForwardModule = struct {
    core: c.ke_render_core_handle = undefined,
    device: *c.ke_gpu_device = undefined,
    ndc: c.ke_ndc_convention = undefined, // backend clip-space convention
    logger: ?*c.ke_logger = null,

    // When false, bindings 7-8 are forced to the engine's default black cubemap
    // regardless of any skybox — the shader still samples it, but IBL is 0.
    ibl_enabled: bool = true,

    // Cross-cutting cids, captured at setup (registered once by the aggregator).
    mesh_cid: c.ke_component_id = undefined,
    transform_cid: c.ke_component_id = undefined,
    camera_cid: c.ke_component_id = undefined,
    light_cid: c.ke_component_id = undefined,
    point_light_cid: c.ke_component_id = undefined,
    spot_light_cid: c.ke_component_id = undefined,
    ambient_cid: c.ke_component_id = undefined,
    skybox_cid: c.ke_component_id = undefined,
    frame_cid: c.ke_component_id = undefined,

    // Borrowed feature modules whose outputs forward consumes (set up first).
    shadow: *ShadowModule = undefined,
    cluster: *ClusterModule = undefined,
    skybox: *SkyboxModule = undefined,

    fwd_lit_pipeline: c.ke_gpu_pipeline = c.KE_GPU_INVALID_HANDLE,
    magenta_pipeline: c.ke_gpu_pipeline = c.KE_GPU_INVALID_HANDLE, // Mechanism-1 "never silent" miss placeholder
    fwd_obj_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE, // set 2, per-object (dynamic offset)
    fwd_obj_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    fwd_frame_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE, // set 0, per-frame
    fwd_frame_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    frame_bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE, // set 0 layout (rebuild bind group on env change)
    env_cubemap: c.ke_texture_handle = .{ .idx = c.KE_HANDLE_NONE }, // currently bound env (default until a skybox is set)

    fwd_writes: [2][*c]const u8 = undefined,
    fwd_reads: [1][*c]const u8 = undefined,
    fwd_io: c.ke_render_pass_io = undefined,
    fwd_access: [13]c.ke_component_access = undefined,
    fwd_access_count: u32 = 0, // < 13 when shadow.enabled is false (no shadow_map READ dependency)
};

// ── Projection helpers (consume the backend NDC convention) ──────────────────
// The view is always built left-handed (the engine owns the world convention).
// The projection absorbs the backend's clip-space quirks (z range + Y flip).
fn makePerspective(ndc: c.ke_ndc_convention, fovy: f32, aspect: f32, near: f32, far: f32) zm.Mat {
    var p = if (ndc.z_zero_to_one != 0)
        zm.perspectiveFovLh(fovy, aspect, near, far)
    else
        zm.perspectiveFovLhGl(fovy, aspect, near, far);
    if (ndc.y_flip != 0) p[1][1] = -p[1][1];
    return p;
}

// Left-handed view from a camera transform (identity rotation → look at origin;
// otherwise the world-matrix basis, looking down local −Z).
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

fn logGpuError(logger: ?*c.ke_logger, err: ?*c.ke_error, what: []const u8) void {
    const lg = logger orelse return;
    const e = err orelse return;
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "{s} failed: {s}", .{ what, e.message }) catch return;
    var ev = c.ke_log_event{ .level = c.KE_LOG_LEVEL_ERROR, .tag = "render_core", .message = msg.ptr };
    lg.log.?(lg, &ev);
}

inline fn moduleOf(user: ?*anyopaque) *ForwardModule {
    return @alignCast(@ptrCast(user.?));
}

// Builds set 0 (per-frame uniform + env cubemap + sampler + shadow/IBL hooks).
// Called at setup and whenever the bound environment cubemap changes (rare —
// at scene load). All 9 bindings are always present (one fixed pipeline
// layout, one shader); shadow.enabled/ibl_enabled only pick which resource
// backs bindings 3-6/7-8: the real render target/env cube when on, or a
// neutral default (1x1 white / black cube) that makes forward_lit.slang's
// hooks a no-op when off.
fn rebuildFrameBindGroup(fwd: *ForwardModule) void {
    const dev = fwd.device;
    const core = fwd.core.ref;
    const env_view = core.*.texture_view.?(core, fwd.env_cubemap); // defaults to black cube when no skybox is set
    const white_view = core.*.texture_view.?(core, .{ .idx = 0 }); // handle 0 = built-in 1x1 white texture
    const black_cube_view = core.*.texture_view.?(core, .{ .idx = c.KE_HANDLE_NONE }); // always resolves to the default black cube
    const smp = core.*.sampler.?(core);

    const shadow_tex_view = if (fwd.shadow.enabled) fwd.shadow.view else white_view;
    const ibl_view = if (fwd.ibl_enabled) env_view else black_cube_view;

    const entries = [9]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = fwd.fwd_frame_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(PerFrame), .texture_view = 0, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = env_view, .sampler = 0 },
        .{ .binding = 2, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
        // Shadow feature (shadow_feature.slang) — reuses the shadow module's lvp
        // uniform (its system uploads the light-view-proj each frame when
        // enabled; otherwise the white default texture always samples 1.0).
        .{ .binding = 3, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = shadow_tex_view, .sampler = 0 },
        .{ .binding = 4, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = fwd.shadow.lvp_uniform, .buffer_offset = 0, .buffer_size = 64, .texture_view = 0, .sampler = 0 },
        .{ .binding = 5, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = shadow_tex_view, .sampler = 0 },
        .{ .binding = 6, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
        // IBL feature (ibl_feature.slang) — same env cube as binding 1 when on;
        // forced to the default black cube when off, regardless of any skybox.
        .{ .binding = 7, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = ibl_view, .sampler = 0 },
        .{ .binding = 8, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
    };

    var err: ?*c.ke_error = null;
    fwd.fwd_frame_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = fwd.frame_bgl,
        .entry_count = 9,
        .entries = &entries,
    }, &err);
    if (err != null) logGpuError(fwd.logger, err, "rebuild frame bind group");
}

pub fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const fwd = moduleOf(user);
    const core = fwd.core.ref;

    // Camera: take the first camera entity + its transform.
    var cam_ents: [*c]c.ke_entity = undefined;
    var cam_data: ?*anyopaque = undefined;
    var cam_count: usize = 0;
    c.ke_system_ctx_query(ctx, fwd.camera_cid, &cam_ents, &cam_data, &cam_count);

    const pc = core.*.begin_pass.?(core, ctx, &fwd.fwd_io);
    if (pc == null) return;

    // No camera — open/close the pass so the hdr target is cleared, then bail.
    if (cam_count == 0) {
        const rp0 = pc.*.begin_render.?(pc);
        rp0.*.end.?(rp0);
        core.*.end_pass.?(core, pc);
        return;
    }

    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_data));
    const cam_tc_raw = c.ke_system_ctx_get(ctx, fwd.transform_cid, cam_ents[0]) orelse {
        const rp0 = pc.*.begin_render.?(pc);
        rp0.*.end.?(rp0);
        core.*.end_pass.?(core, pc);
        return;
    };
    const cam_tc: *const c.ke_transform_component = @ptrCast(@alignCast(cam_tc_raw));

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    const view = cameraView(cam_tc);
    // ke_camera_component.fov is in degrees (the cross-backend convention).
    const fov_rad = cam.fov * @as(f32, std.math.pi / 180.0);
    const proj = makePerspective(fwd.ndc, fov_rad, aspect, cam.near_plane, cam.far_plane);
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
    c.ke_system_ctx_query(ctx, fwd.skybox_cid, &sky_ents, &sky_data, &sky_count);
    const want_env: c.ke_texture_handle = if (sky_count != 0)
        (@as(*const SkyboxComp, @ptrCast(@alignCast(sky_data)))).cubemap
    else
        .{ .idx = c.KE_HANDLE_NONE };
    if (want_env.idx != fwd.env_cubemap.idx) {
        fwd.env_cubemap = want_env;
        rebuildFrameBindGroup(fwd);
    }

    // Per-frame: camera + lights. All light terms default off; each present light
    // turns on its contribution (a scene with only point lights has no directional).
    var frame: PerFrame = .{
        .camera_pos = .{ cam_tc.position.x, cam_tc.position.y, cam_tc.position.z, 1.0 },
        .light_dir = .{ -0.4, -1.0, -0.3, 0.0 },
        .light_color = .{ 1.0, 1.0, 1.0, 1.0 },
        .ambient = .{ 0.0, 0.0, 0.0, 0.0 },
        .sky_view_proj = undefined,
        .shadow_params = .{ 0.0, 0.0, 0.0, 0.0 }, // x=shadow active, z=directional active
        .view = undefined,
    };
    zm.storeMat(frame.sky_view_proj[0..], sky_vp);
    zm.storeMat(frame.view[0..], view); // for the fragment's cluster z slice

    // Clustered-lights feature's own UBO (cluster_feature.slang, set 3 binding
    // 6) — the one seam where forward reaches into cluster_module.zig, since
    // the viewport component is only known from forward's own backbuffer query.
    cluster_module.uploadGrid(fwd.cluster, bw, bh, cam.near_plane, cam.far_plane);

    // Directional light (first entity). Present → enable the directional term +
    // its shadow map; its ambient seeds the scene ambient. Point/spot lights are
    // accumulated from the clustered storage buffers (the cull pass binned them).
    var li_ents: [*c]c.ke_entity = undefined;
    var li_data: ?*anyopaque = undefined;
    var li_count: usize = 0;
    c.ke_system_ctx_query(ctx, fwd.light_cid, &li_ents, &li_data, &li_count);
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
    c.ke_system_ctx_query(ctx, fwd.ambient_cid, &am_ents, &am_data, &am_count);
    if (am_count != 0) {
        const al: *const AmbientComp = @ptrCast(@alignCast(am_data));
        frame.ambient = .{ al.color[0], al.color[1], al.color[2], 0.0 };
    }

    core.*.upload.?(core, fwd.fwd_frame_uniform, 0, &frame, @sizeOf(PerFrame));

    // Meshes: build + upload one uniform region per draw (queue writes land before
    // the recorded draws, so each dynamic offset reads its own object).
    var ents: [*c]c.ke_entity = undefined;
    var data: ?*anyopaque = undefined;
    var count: usize = 0;
    c.ke_system_ctx_query(ctx, fwd.mesh_cid, &ents, &data, &count);
    const meshes: [*c]const c.ke_mesh_component = @ptrCast(@alignCast(data));
    const n: u32 = @intCast(@min(count, MAX_DRAWS));

    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const tc_raw = c.ke_system_ctx_get(ctx, fwd.transform_cid, ents[i]) orelse continue;
        const tc: *const c.ke_transform_component = @ptrCast(@alignCast(tc_raw));
        const model = zm.loadMat(tc.world_matrix.m[0..]);
        const mvp = zm.mul(model, view_proj);

        var u: PerObject = undefined;
        zm.storeMat(u.mvp[0..], mvp);
        zm.storeMat(u.model[0..], model);
        core.*.upload.?(core, fwd.fwd_obj_uniform, i * UNIFORM_STRIDE, &u, @sizeOf(PerObject));
    }

    const rp = pc.*.begin_render.?(pc);
    // Sets 0 and 3 (per-frame + lights) share the same layout across the
    // forward_lit and magenta pipelines, so they stay bound while the per-mesh
    // pipeline switches below.
    rp.*.set_bind_group.?(rp, 0, fwd.fwd_frame_bind_group, null, 0); // set 0: per-frame
    rp.*.set_bind_group.?(rp, 3, fwd.cluster.fwd_light_bind_group, null, 0); // set 3: lights
    i = 0;
    while (i < n) : (i += 1) {
        var vbo: c.ke_gpu_buffer = 0;
        var ibo: c.ke_gpu_buffer = 0;
        var idx_count: u32 = 0;
        if (core.*.mesh_buffers.?(core, meshes[i].mesh, &vbo, &ibo, &idx_count) == 0) continue;
        const offset: u32 = i * UNIFORM_STRIDE;
        // PSO selection (Mechanism 1): a mesh with no assigned material draws
        // magenta ("never silent"); an assigned material draws the IMaterial path.
        const has_material = meshes[i].material.idx != c.KE_HANDLE_NONE;
        rp.*.set_pipeline.?(rp, if (has_material) fwd.fwd_lit_pipeline else fwd.magenta_pipeline);
        const mat_bg = core.*.material_bind_group.?(core, meshes[i].material);
        rp.*.set_bind_group.?(rp, 1, mat_bg, null, 0); // set 1: per-material
        rp.*.set_bind_group.?(rp, 2, fwd.fwd_obj_bind_group, &offset, 1); // set 2: per-object
        rp.*.set_vertex_buffer.?(rp, 0, vbo, 0);
        rp.*.set_index_buffer.?(rp, ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.*.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
    }

    // Skybox last — depth LEQUAL, no depth write: fills only the background pixels
    // the opaque meshes did not cover, within the same render pass (no load-op).
    skybox_module.draw(fwd.skybox, rp, fwd.fwd_frame_bind_group);

    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

// Sets up the forward pass's own resources. shadow/cluster/skybox are already
// set up by the aggregator and passed as borrowed pointers — forward consumes
// their handles (shadow map + lvp into set 0, cluster light lists into set 3,
// skybox drawn inside the render pass), it does not create them.
pub fn setup(fwd: *ForwardModule, dev: *c.ke_gpu_device, core: c.ke_render_core_handle,
             ndc: c.ke_ndc_convention, logger: ?*c.ke_logger, ibl_enabled: bool,
             mesh_cid: c.ke_component_id, transform_cid: c.ke_component_id,
             camera_cid: c.ke_component_id, light_cid: c.ke_component_id,
             point_light_cid: c.ke_component_id, spot_light_cid: c.ke_component_id,
             ambient_cid: c.ke_component_id, skybox_cid: c.ke_component_id,
             frame_cid: c.ke_component_id, shadow: *ShadowModule, cluster: *ClusterModule,
             skybox: *SkyboxModule, out_error: [*c][*c]c.ke_error) bool {
    fwd.core = core;
    fwd.device = dev;
    fwd.ndc = ndc;
    fwd.logger = logger;
    fwd.ibl_enabled = ibl_enabled;
    fwd.mesh_cid = mesh_cid;
    fwd.transform_cid = transform_cid;
    fwd.camera_cid = camera_cid;
    fwd.light_cid = light_cid;
    fwd.point_light_cid = point_light_cid;
    fwd.spot_light_cid = spot_light_cid;
    fwd.ambient_cid = ambient_cid;
    fwd.skybox_cid = skybox_cid;
    fwd.frame_cid = frame_cid;
    fwd.shadow = shadow;
    fwd.cluster = cluster;
    fwd.skybox = skybox;
    fwd.env_cubemap = .{ .idx = c.KE_HANDLE_NONE };

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

    // Set 0 — per-frame uniform + env cubemap + sampler + the shadow and IBL
    // hook resources (bindings 3-8), always present: one fixed layout, one
    // shader, for every shadow/ibl combination. Which resource backs 3-6/7-8 is
    // a neutral default (1x1 white / black cube) when the feature is off, the
    // real render target/env cube when on (rebuildFrameBindGroup).
    const frame_bgl_entries = [9]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 1, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = c.KE_GPU_TEXTURE_DIM_CUBE },
        .{ .binding = 2, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
        // Set-0 append rather than a new set — the C ABI's bind_group_layouts
        // array is fixed at 4 entries (sets 0-3), but one set's own entry list
        // has no such cap.
        .{ .binding = 3, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 4, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 5, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 6, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 7, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = c.KE_GPU_TEXTURE_DIM_CUBE },
        .{ .binding = 8, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    const frame_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 9,
        .entries = &frame_bgl_entries,
    });
    fwd.frame_bgl = frame_bgl;

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
    pp.bind_group_layouts[0] = frame_bgl; // set 0: per-frame (camera + light)
    pp.bind_group_layouts[1] = core.ref.*.material_layout.?(core.ref); // set 1: per-material
    pp.bind_group_layouts[2] = obj_bgl; // set 2: per-object (transform)
    pp.bind_group_layouts[3] = cluster.light_set_bgl; // set 3: clustered light lists
    pp.bind_group_layout_count = 4;
    pp.color_target_format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT; // HDR intermediate

    // Material-authored path: one shader pair covers every shadow/ibl combination
    // — the hooks read neutral-default resources bound by rebuildFrameBindGroup.
    const lit_vs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(mat_test_flat_vs_wgsl),
        .byte_size = mat_test_flat_vs_wgsl.len,
        .entry_point = "mat_test_flat.vs",
    }, out_error);
    if (lit_vs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, lit_vs);
    const lit_fs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(mat_test_flat_fs_wgsl),
        .byte_size = mat_test_flat_fs_wgsl.len,
        .entry_point = "mat_test_flat.fs",
    }, out_error);
    if (lit_fs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, lit_fs);
    pp.vertex_module = lit_vs;
    pp.fragment_module = lit_fs;
    fwd.fwd_lit_pipeline = dev.create_render_pipeline.?(dev, &pp);
    if (fwd.fwd_lit_pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "forward_lit pass: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    // Magenta placeholder — Mechanism 1 "never silent" miss fallback. Same
    // pipeline layout + vertex layout; fragment outputs solid magenta.
    const mag_vs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(magenta_vs_wgsl),
        .byte_size = magenta_vs_wgsl.len,
        .entry_point = "magenta.vs",
    }, out_error);
    if (mag_vs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, mag_vs);
    const mag_fs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(magenta_fs_wgsl),
        .byte_size = magenta_fs_wgsl.len,
        .entry_point = "magenta.fs",
    }, out_error);
    if (mag_fs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, mag_fs);
    pp.vertex_module = mag_vs;
    pp.fragment_module = mag_fs;
    fwd.magenta_pipeline = dev.create_render_pipeline.?(dev, &pp);
    if (fwd.magenta_pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "magenta placeholder: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    // Set 2 — per-object ring (one dynamic-offset region per draw).
    fwd.fwd_obj_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = UNIFORM_STRIDE * MAX_DRAWS,
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (fwd.fwd_obj_uniform == c.KE_GPU_INVALID_HANDLE) return false;
    const obj_bg_entry = c.ke_gpu_bind_group_entry{
        .binding = 0,
        .type = c.KE_GPU_BINDING_TYPE_BUFFER,
        .buffer = fwd.fwd_obj_uniform,
        .buffer_offset = 0,
        .buffer_size = @sizeOf(PerObject),
        .texture_view = 0,
        .sampler = 0,
    };
    fwd.fwd_obj_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = obj_bgl,
        .entry_count = 1,
        .entries = &obj_bg_entry,
    }, out_error);
    if (fwd.fwd_obj_bind_group == c.KE_GPU_INVALID_HANDLE) return false;

    // Set 0 — per-frame uniform + env cubemap + sampler + shadow map. The bind
    // group is rebuilt (rebuildFrameBindGroup) when the bound environment changes.
    fwd.fwd_frame_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = @sizeOf(PerFrame),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (fwd.fwd_frame_uniform == c.KE_GPU_INVALID_HANDLE) return false;
    rebuildFrameBindGroup(fwd);

    // Transient depth target, sized to the backbuffer (the core resolves the
    // scale against its current swapchain size).
    const depth_cid = core.ref.*.declare.?(core.ref, &c.ke_render_resource_desc{
        .name = "depth",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0,
        .height = 0,
        .scale_x = 1.0,
        .scale_y = 1.0,
    }, null);

    // HDR intermediate buffer (Rgba16Float). The forward renders here; the
    // tonemap pass resolves it to the swapchain (backbuffer).
    const hdr_cid = core.ref.*.declare.?(core.ref, &c.ke_render_resource_desc{
        .name = "hdr",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0,
        .height = 0,
        .scale_x = 1.0,
        .scale_y = 1.0,
    }, null);

    // Forward writes to "hdr" (not directly to backbuffer); tonemap resolves.
    fwd.fwd_writes = .{ "hdr", "depth" };
    fwd.fwd_reads = .{"shadow_map"};
    fwd.fwd_io = std.mem.zeroes(c.ke_render_pass_io);
    fwd.fwd_io.writes = @ptrCast(&fwd.fwd_writes);
    fwd.fwd_io.writes_count = 2;
    // No "shadow_map" resource exists at all when shadow.enabled is false —
    // declaring a read dependency on it here would reference an undeclared
    // resource.
    if (fwd.shadow.enabled) {
        fwd.fwd_io.reads = @ptrCast(&fwd.fwd_reads);
        fwd.fwd_io.reads_count = 1;
    }
    fwd.fwd_io.cmd_slot = 3; // forward pass → frame command slot 3 (after cull)

    var fac: u32 = 0;
    fwd.fwd_access[fac] = .{ .cid = hdr_cid, .access = c.KE_ACCESS_WRITE };
    fac += 1;
    fwd.fwd_access[fac] = .{ .cid = depth_cid, .access = c.KE_ACCESS_WRITE };
    fac += 1;
    fwd.fwd_access[fac] = .{ .cid = mesh_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    fwd.fwd_access[fac] = .{ .cid = transform_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    fwd.fwd_access[fac] = .{ .cid = camera_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    fwd.fwd_access[fac] = .{ .cid = light_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    fwd.fwd_access[fac] = .{ .cid = skybox_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    if (fwd.shadow.enabled) {
        fwd.fwd_access[fac] = .{ .cid = core.ref.*.cid.?(core.ref, "shadow_map"), .access = c.KE_ACCESS_READ };
        fac += 1;
    }
    fwd.fwd_access[fac] = .{ .cid = frame_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    fwd.fwd_access[fac] = .{ .cid = point_light_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    fwd.fwd_access[fac] = .{ .cid = spot_light_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    fwd.fwd_access[fac] = .{ .cid = ambient_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    fwd.fwd_access[fac] = .{ .cid = cluster.clusters_cid, .access = c.KE_ACCESS_READ }; // after the cull pass
    fac += 1;
    fwd.fwd_access_count = fac;
    return true;
}
