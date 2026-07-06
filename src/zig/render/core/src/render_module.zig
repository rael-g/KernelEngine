const std = @import("std");
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const shadow_module = @import("shadow_module.zig");
const ShadowModule = shadow_module.ShadowModule;
const skybox_module = @import("skybox_module.zig");
const SkyboxModule = skybox_module.SkyboxModule;
const cluster_module = @import("cluster_module.zig");
const ClusterModule = cluster_module.ClusterModule;

// Compiled into the ke_render_core library (folded here because a separate Zig
// DLL cannot link another Zig DLL's import lib on Windows). Calls the render
// core factory in-lib; the device is caller-created and borrowed. Shared with
// shadow_module.zig via cimport.zig — a second @cImport of the same headers
// would produce distinct, incompatible types for the same C struct.
pub const c = cimport.c;

const gpa = std.heap.c_allocator;

const ExecFn = ?*const fn (?*c.ke_system_ctx, ?*anyopaque, f32) callconv(.c) void;

// Pass shaders, compiled Slang -> WGSL by CMake (one module per stage; a
// cross-stage uniform can't be declared twice in one WGSL module). The shadow
// pass's, skybox's, and the cluster cull's own shaders are embedded in
// shadow_module.zig / skybox_module.zig / cluster_module.zig — this file no
// longer knows their names.
const tonemap_vs_wgsl = @embedFile("tonemap.vs.wgsl");
const tonemap_fs_wgsl = @embedFile("tonemap.fs.wgsl");
// Material-authored forward path + magenta miss placeholder. A single shader
// pair now covers every shadow/IBL opt-in combination — the hooks read
// neutral-default resources (see forward_lit.slang) instead of being linked
// in as separate generic specializations, so there is no per-combo variant
// to embed here anymore.
const mat_test_flat_vs_wgsl = @embedFile("mat_test_flat.vs.wgsl");
const mat_test_flat_fs_wgsl = @embedFile("mat_test_flat.fs.wgsl");
const magenta_vs_wgsl = @embedFile("magenta.vs.wgsl");
const magenta_fs_wgsl = @embedFile("magenta.fs.wgsl");

// Clustered-forward grid + per-froxel cap defaults. These are workload-tuning
// values the caller can override via ke_render_cluster_params (0 field = keep
// the default below) — not engine-imposed limits. A froxel holding more
// concurrently overlapping lights than max_lights_per_cluster silently drops
// the excess (a real correctness limit of the algorithm), so a caller running
// a denser scene than these defaults suit should raise the field rather than
// hit that ceiling. The grid/cull machinery itself lives in cluster_module.zig
// now; these defaults stay here because they're resolved from the caller's
// ke_render_cluster_params before cluster_module.setup is even called.
const DEFAULT_GRID_X: u32 = 32;
const DEFAULT_GRID_Y: u32 = 18;
const DEFAULT_GRID_Z: u32 = 24;
const DEFAULT_MAX_LIGHTS_PER_CLUSTER: u32 = 256;

const MAX_DRAWS = 512;
const UNIFORM_STRIDE = 256; // dynamic-offset alignment (>= minUniformBufferOffsetAlignment)

// Set 2 — per-object transform (dynamic offset). Matches forward.slang PerObject.
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
    // light_vp moved to the shadow feature's own UBO (reuses shadow_lvp_uniform).
    // shadow_params.x (shadow active) is vestigial now that which
    // ILightVisibility is linked decides this at compile time; kept for
    // forward.slang (dead pipeline) compatibility, harmless either way.
    shadow_params: [4]f32, // x = shadow active (vestigial), z = directional active
    view: [16]f32, // world→view (for the fragment's cluster z slice)
};

// Mirrors the C# AmbientLightComponent { Vector3 Color } (registered "AmbientLight").
const AmbientComp = extern struct { color: [3]f32 };

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
    logger: ?*c.ke_logger, // borrowed, optional — runtime diagnostics route through it when present

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

    // Forward pass: forward_lit composed with the built-in flat material via
    // the IMaterial conformance. Scene meshes draw through this — a single
    // pipeline covers every shadow/IBL combination now; the hooks read
    // neutral-default resources (see rebuildFrameBindGroup) instead of a
    // separately-compiled shader variant. magenta_pipeline is the Mechanism-1
    // "never silent" miss placeholder.
    fwd_lit_pipeline: c.ke_gpu_pipeline,
    // Same idea for ambient/reflection: when false, bindings 7-8 are forced to
    // the engine's default black cubemap regardless of any skybox — the
    // shader still samples it unconditionally, but the contribution is 0.
    ibl_enabled: bool,
    magenta_pipeline: c.ke_gpu_pipeline,
    fwd_obj_bind_group: c.ke_gpu_bind_group, // set 2, per-object (dynamic offset)
    fwd_obj_uniform: c.ke_gpu_buffer,
    fwd_frame_bind_group: c.ke_gpu_bind_group, // set 0, per-frame
    fwd_frame_uniform: c.ke_gpu_buffer,
    fwd_writes: [2][*c]const u8,
    fwd_reads: [1][*c]const u8,
    fwd_io: c.ke_render_pass_io,
    fwd_access: [13]c.ke_component_access,
    fwd_access_count: u32, // < 13 when shadow.enabled is false (no shadow_map READ dependency)
    mesh_cid: c.ke_component_id,
    transform_cid: c.ke_component_id,
    camera_cid: c.ke_component_id,
    light_cid: c.ke_component_id,
    point_light_cid: c.ke_component_id,
    spot_light_cid: c.ke_component_id,
    ambient_cid: c.ke_component_id,
    skybox_cid: c.ke_component_id,

    // Skybox — extracted into skybox_module.zig (setup + draw, no runtime
    // system of its own: it draws inside the forward pass's render pass).
    skybox: SkyboxModule,
    frame_bgl: c.ke_gpu_bind_group_layout, // set 0 layout (rebuild bind group on env change)
    env_cubemap: c.ke_texture_handle, // currently bound env (default until a skybox is set)

    // Shadow-depth pass — extracted as the §9.8 decomposition pilot into its
    // own file (shadow_module.zig): owns its GPU resources, its own runtime
    // system, and the cids it needs, taking only borrowed cross-cutting refs
    // (core, ndc, mesh/transform/light/frame cids) at setup.
    shadow: ShadowModule,

    // Clustered forward + light cull — extracted into cluster_module.zig: owns
    // the grid workload shape, the 6 storage buffers, the cull compute
    // pipeline + its own "render.cull" runtime system, and the forward's set-3
    // read-only bind group. forwardSys still calls into it once per frame
    // (uploadGrid) and binds its set-3 group directly during the draw loop —
    // the one real coupling seam left after the shadow/skybox extractions.
    cluster: ClusterModule,

    // ACES tonemapping pass — reads "hdr" (Rgba16Float), writes "backbuffer".
    tonemap_pipeline: c.ke_gpu_pipeline,
    tonemap_bgl: c.ke_gpu_bind_group_layout,
    tonemap_bind_group: c.ke_gpu_bind_group,
    tonemap_writes: [1][*c]const u8,
    tonemap_reads: [1][*c]const u8,
    tonemap_io: c.ke_render_pass_io,
    tonemap_access: [2]c.ke_component_access,
    hdr_cid: c.ke_component_id,

    // UI overlay — screen-space quads (Font/Label text, solid rects) composited
    // over the tonemapped scene. Loads (doesn't clear) the backbuffer; the core
    // owns the pipeline + per-frame quad list (ke_render_core.ui_quad/ui_draw).
    ui_writes: [1][*c]const u8,
    ui_io: c.ke_render_pass_io,
    ui_access: [1]c.ke_component_access,
};

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

// A GPU resource create call failed on a path with no out_error slot to bubble
// through (a runtime rebuild triggered by an environment change, not the
// initial setup path) — route the captured ke_error through the logger
// instead of losing it silently.
fn logGpuError(logger: ?*c.ke_logger, err: ?*c.ke_error, what: []const u8) void {
    const lg = logger orelse return;
    const e = err orelse return;
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "{s} failed: {s}", .{ what, e.message }) catch return;
    var ev = c.ke_log_event{ .level = c.KE_LOG_LEVEL_ERROR, .tag = "render_core", .message = msg.ptr };
    lg.log.?(lg, &ev);
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

    const pc = core.*.begin_pass.?(core, ctx, &st.fwd_io);
    if (pc == null) return;

    // No camera — open/close the pass so the hdr target is cleared, then bail.
    if (cam_count == 0) {
        const rp0 = pc.*.begin_render.?(pc);
        rp0.*.end.?(rp0);
        core.*.end_pass.?(core, pc);
        return;
    }

    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_data));
    const cam_tc_raw = c.ke_system_ctx_get(ctx, st.transform_cid, cam_ents[0]) orelse {
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
        .shadow_params = .{ 0.0, 0.0, 0.0, 0.0 }, // x=shadow active, z=directional active
        .view = undefined,
    };
    zm.storeMat(frame.sky_view_proj[0..], sky_vp);
    zm.storeMat(frame.view[0..], view); // for the fragment's cluster z slice
    // light_vp is uploaded once by shadowSys into shadow_lvp_uniform (set 4);
    // the shadow feature's bind group reuses that buffer directly — no
    // duplicate computation/upload needed here.

    // Clustered-lights feature's own UBO (cluster_feature.slang, set 3 binding
    // 6) — the one seam where forward reaches into cluster_module.zig, since
    // the viewport component is only known from forward's own backbuffer query.
    cluster_module.uploadGrid(&st.cluster, bw, bh, cam.near_plane, cam.far_plane);

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
    // Sets 0 and 3 (per-frame + lights) share the same layout across the
    // forward_lit and magenta pipelines, so they stay bound while the per-mesh
    // pipeline switches below.
    rp.*.set_bind_group.?(rp, 0, st.fwd_frame_bind_group, null, 0); // set 0: per-frame
    rp.*.set_bind_group.?(rp, 3, st.cluster.fwd_light_bind_group, null, 0); // set 3: lights
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
        rp.*.set_pipeline.?(rp, if (has_material) st.fwd_lit_pipeline else st.magenta_pipeline);
        const mat_bg = core.*.material_bind_group.?(core, meshes[i].material);
        rp.*.set_bind_group.?(rp, 1, mat_bg, null, 0); // set 1: per-material
        rp.*.set_bind_group.?(rp, 2, st.fwd_obj_bind_group, &offset, 1); // set 2: per-object
        rp.*.set_vertex_buffer.?(rp, 0, vbo, 0);
        rp.*.set_index_buffer.?(rp, ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.*.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
    }
    // Skybox needs the monolithic-forward-compatible pipeline state re-established
    // via its own pipeline below; the per-mesh selection above left fwd_lit/magenta
    // bound, which is fine — the skybox sets its own pipeline next.

    // Skybox last — depth LEQUAL, no depth write: fills only the background pixels
    // the opaque meshes did not cover, within the same render pass (no load-op).
    skybox_module.draw(&st.skybox, rp, st.fwd_frame_bind_group);

    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

// Builds set 0 (per-frame uniform + env cubemap + sampler + shadow/IBL hooks).
// Called at setup and whenever the bound environment cubemap changes (rare —
// at scene load). All 9 bindings are always present (one fixed pipeline
// layout, one shader) — shadow_enabled/ibl_enabled only pick which resource
// backs bindings 3-6/7-8: the real render target/env cube when on, or a
// neutral default (1x1 white / black cube) that makes forward_lit.slang's
// hooks a no-op when off. See project doctrine: neutral-default resources
// realize opt-in composition without a shader variant per combination.
fn rebuildFrameBindGroup(st: *ModuleState) void {
    const dev = st.device;
    const core = st.core.ref;
    const env_view = core.*.texture_view.?(core, st.env_cubemap); // defaults to black cube when no skybox is set
    const white_view = core.*.texture_view.?(core, .{ .idx = 0 }); // handle 0 = built-in 1x1 white texture
    const black_cube_view = core.*.texture_view.?(core, .{ .idx = c.KE_HANDLE_NONE }); // always resolves to the default black cube
    const smp = core.*.sampler.?(core);

    const shadow_tex_view = if (st.shadow.enabled) st.shadow.view else white_view;
    const ibl_view = if (st.ibl_enabled) env_view else black_cube_view;

    const entries = [9]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = st.fwd_frame_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(PerFrame), .texture_view = 0, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = env_view, .sampler = 0 },
        .{ .binding = 2, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
        // Shadow feature (shadow_feature.slang) — reuses shadow_lvp_uniform
        // (shadowSys uploads the light-view-proj each frame when shadow_enabled;
        // otherwise the buffer stays zeroed and unread, since the white default
        // texture always samples 1.0 regardless of the computed coordinate).
        .{ .binding = 3, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = shadow_tex_view, .sampler = 0 },
        .{ .binding = 4, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = st.shadow.lvp_uniform, .buffer_offset = 0, .buffer_size = 64, .texture_view = 0, .sampler = 0 },
        .{ .binding = 5, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = shadow_tex_view, .sampler = 0 },
        .{ .binding = 6, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
        // IBL feature (ibl_feature.slang) — same env cube as binding 1 when on;
        // forced to the default black cube when off, regardless of any skybox.
        .{ .binding = 7, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = ibl_view, .sampler = 0 },
        .{ .binding = 8, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
    };

    var err: ?*c.ke_error = null;
    st.fwd_frame_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = st.frame_bgl,
        .entry_count = 9,
        .entries = &entries,
    }, &err);
    if (err != null) logGpuError(st.logger, err, "rebuild frame bind group");
}

fn forwardSetup(st: *ModuleState, e: *c.ke_ecs, grid_x: u32, grid_y: u32, grid_z: u32,
                 max_lights_per_cluster: u32, out_error: [*c][*c]c.ke_error) bool {
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
    st.point_light_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_POINT_LIGHT, @sizeOf(cluster_module.PointLightComp));
    st.spot_light_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_SPOT_LIGHT, @sizeOf(cluster_module.SpotLightComp));
    st.ambient_cid = e.component_register.?(e, "AmbientLight", @sizeOf(AmbientComp));
    st.skybox_cid = e.component_register.?(e, "Skybox", @sizeOf(SkyboxComp));
    st.env_cubemap = .{ .idx = c.KE_HANDLE_NONE }; // default (black) cube until a skybox is set

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
    // environment cubemap + sampler (fs, for skybox + IBL) + the shadow and IBL
    // hook resources (bindings 3-8), always present: one fixed layout, one
    // shader, for every shadow_enabled/ibl_enabled combination.
    // shadow_enabled/ibl_enabled gate which resource backs 3-6/7-8
    // (rebuildFrameBindGroup) — a neutral default (1x1 white / black cube)
    // when the feature is off, the real render target/env cube when on.
    const frame_bgl_entries = [9]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 1, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = c.KE_GPU_TEXTURE_DIM_CUBE },
        .{ .binding = 2, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
        // Set-0 append rather than a new set — the C ABI's bind_group_layouts
        // array is fixed at 4 entries (sets 0-3), but one set's own entry list
        // has no such cap.
        .{ .binding = 3, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 }, // legacy shadow texture, superset entry
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
    // Fully owned by cluster_module.zig now; render_module.zig only forwards
    // the grid workload shape (resolved from ke_render_cluster_params by the
    // caller) and the cross-cutting cids it needs.
    if (!cluster_module.setup(&st.cluster, dev, e, st.core, st.logger, grid_x, grid_y, grid_z, max_lights_per_cluster,
                               st.point_light_cid, st.spot_light_cid, st.transform_cid, st.camera_cid, st.frame_cid, out_error)) return false;
    pp.bind_group_layouts[0] = frame_bgl; // set 0: per-frame (camera + light)
    pp.bind_group_layouts[1] = st.core.ref.*.material_layout.?(st.core.ref); // set 1: per-material
    pp.bind_group_layouts[2] = obj_bgl; // set 2: per-object (transform)
    pp.bind_group_layouts[3] = st.cluster.light_set_bgl; // set 3: clustered light lists
    pp.bind_group_layout_count = 4;
    pp.color_target_format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT; // HDR intermediate

    // Material-authored path: the engine ForwardLit pass composed with the
    // built-in flat material via the IMaterial conformance. One shader pair
    // covers every shadow_enabled/ibl_enabled combination — the hooks read
    // neutral-default resources bound by rebuildFrameBindGroup, not a
    // separately-compiled shader variant.
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
    st.fwd_lit_pipeline = dev.create_render_pipeline.?(dev, &pp);
    if (st.fwd_lit_pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "forward_lit pass: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    // Magenta placeholder — Mechanism 1 "never silent" miss fallback. Same
    // pipeline layout (so the draw loop binds it uniformly) + vertex layout;
    // fragment outputs solid magenta.
    pp.bind_group_layouts[3] = st.cluster.light_set_bgl;
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
    st.magenta_pipeline = dev.create_render_pipeline.?(dev, &pp);
    if (st.magenta_pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "magenta placeholder: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    // Set 2 — per-object ring (one dynamic-offset region per draw).
    st.fwd_obj_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = UNIFORM_STRIDE * MAX_DRAWS,
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (st.fwd_obj_uniform == c.KE_GPU_INVALID_HANDLE) return false;
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
    }, out_error);
    if (st.fwd_obj_bind_group == c.KE_GPU_INVALID_HANDLE) return false;

    // Shadow-depth pass: targets + pipeline + per-pass uniforms, entirely
    // owned by shadow_module.zig now. It always allocates lvp_uniform (tiny,
    // 64 bytes — the forward shader's neutral-default hook resource) but the
    // expensive resources (shadow_map/shadow_depth render target, pipeline,
    // per-draw buffers, "render.shadow" system) only when st.shadow.enabled.
    if (!shadow_module.setup(&st.shadow, dev, st.core, st.ndc, st.shadow.enabled,
                             st.mesh_cid, st.transform_cid, st.light_cid, st.frame_cid, out_error)) return false;

    // Set 0 — per-frame uniform + env cubemap + sampler + shadow map. The bind
    // group is rebuilt (rebuildFrameBindGroup) when the bound environment changes.
    st.fwd_frame_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = @sizeOf(PerFrame),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (st.fwd_frame_uniform == c.KE_GPU_INVALID_HANDLE) return false;
    rebuildFrameBindGroup(st);

    // Skybox pipeline + geometry — owned by skybox_module.zig now, sharing
    // frame_bgl (set 0) with the forward/magenta pipelines.
    if (!skybox_module.setup(&st.skybox, dev, frame_bgl, out_error)) return false;

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

    // HDR intermediate buffer (Rgba16Float). The forward renders here; the
    // tonemap pass resolves it to the swapchain (backbuffer).
    st.hdr_cid = st.core.ref.*.declare.?(st.core.ref, &c.ke_render_resource_desc{
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
    st.fwd_writes = .{ "hdr", "depth" };
    st.fwd_reads = .{"shadow_map"};
    st.fwd_io = std.mem.zeroes(c.ke_render_pass_io);
    st.fwd_io.writes = @ptrCast(&st.fwd_writes);
    st.fwd_io.writes_count = 2;
    // No "shadow_map" resource exists at all when shadow.enabled is false —
    // declaring a read dependency on it here would reference an undeclared
    // resource.
    if (st.shadow.enabled) {
        st.fwd_io.reads = @ptrCast(&st.fwd_reads);
        st.fwd_io.reads_count = 1;
    }
    st.fwd_io.cmd_slot = 3; // forward pass → frame command slot 3 (after cull)

    var fac: u32 = 0;
    st.fwd_access[fac] = .{ .cid = st.hdr_cid, .access = c.KE_ACCESS_WRITE };
    fac += 1;
    st.fwd_access[fac] = .{ .cid = depth_cid, .access = c.KE_ACCESS_WRITE };
    fac += 1;
    st.fwd_access[fac] = .{ .cid = st.mesh_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    st.fwd_access[fac] = .{ .cid = st.transform_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    st.fwd_access[fac] = .{ .cid = st.camera_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    st.fwd_access[fac] = .{ .cid = st.light_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    st.fwd_access[fac] = .{ .cid = st.skybox_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    if (st.shadow.enabled) {
        st.fwd_access[fac] = .{ .cid = st.core.ref.*.cid.?(st.core.ref, "shadow_map"), .access = c.KE_ACCESS_READ };
        fac += 1;
    }
    st.fwd_access[fac] = .{ .cid = st.frame_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    st.fwd_access[fac] = .{ .cid = st.point_light_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    st.fwd_access[fac] = .{ .cid = st.spot_light_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    st.fwd_access[fac] = .{ .cid = st.ambient_cid, .access = c.KE_ACCESS_READ };
    fac += 1;
    st.fwd_access[fac] = .{ .cid = st.cluster.clusters_cid, .access = c.KE_ACCESS_READ }; // after the cull pass
    fac += 1;
    st.fwd_access_count = fac;
    return true;
}

// ── ACES tonemapping pass ─────────────────────────────────────────────────────
// Reads the HDR buffer written by the forward pass and resolves it to the
// swapchain via the ACES fitted curve (Narkowicz 2015).

fn tonemapSys(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    const core = st.core.ref;
    const dev = st.device;

    const pc = core.*.begin_pass.?(core, ctx, &st.tonemap_io);
    if (pc == null) return;

    // Resolve the HDR texture view for this frame and rebuild the bind group.
    const hdr_view = pc.*.read.?(pc, "hdr");
    const samp = core.*.sampler.?(core);
    const entries = [2]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = hdr_view, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = samp },
    };
    // Destroy the previous frame's bind group before creating the new one.
    if (st.tonemap_bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, st.tonemap_bind_group);
    var err: ?*c.ke_error = null;
    st.tonemap_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = st.tonemap_bgl,
        .entry_count = 2,
        .entries = &entries,
    }, &err);
    if (err != null) logGpuError(st.logger, err, "tonemap bind group");

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, st.tonemap_pipeline);
    rp.*.set_bind_group.?(rp, 0, st.tonemap_bind_group, null, 0);
    rp.*.draw.?(rp, 3, 1, 0, 0); // fullscreen triangle — no vertex buffer needed
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

// UI overlay pass — draws whatever ui_quad calls (Font/Label systems, game HUD
// code) queued this frame. The core owns the pipeline and quad list entirely;
// this just forwards ctx/io so ui_draw can begin/end its own pass.
fn uiSys(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    st.core.ref.*.ui_draw.?(st.core.ref, ctx, &st.ui_io);
}

fn tonemapSetup(st: *ModuleState, out_error: [*c][*c]c.ke_error) bool {
    const dev = st.device;

    const vs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{ .code = @ptrCast(tonemap_vs_wgsl), .byte_size = tonemap_vs_wgsl.len, .entry_point = "tonemap.vs" }, out_error);
    defer dev.destroy_shader_module.?(dev, vs);
    const fs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{ .code = @ptrCast(tonemap_fs_wgsl), .byte_size = tonemap_fs_wgsl.len, .entry_point = "tonemap.fs" }, out_error);
    defer dev.destroy_shader_module.?(dev, fs);

    // Set 0: { texture2D t_hdr @binding(0), sampler s_hdr @binding(1) }
    const bgl_entries = [2]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = c.KE_GPU_TEXTURE_DIM_2D },
        .{ .binding = 1, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    const bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 2,
        .entries = &bgl_entries,
    });

    st.tonemap_bgl = bgl; // kept alive for per-frame bind group creation in tonemapSys
    var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    pp.vertex_module   = vs;
    pp.vertex_entry    = "vs_main";
    pp.fragment_module = fs;
    pp.fragment_entry  = "fs_main";
    pp.bind_group_layouts[0] = bgl;
    pp.bind_group_layout_count = 1;
    pp.color_target_format = 0; // swapchain surface format
    pp.blend_state.write_mask = 0x0F;
    // no depth test — fullscreen triangle pass over backbuffer
    pp.depth_stencil.depth_test_enabled = 0;
    pp.depth_stencil.depth_write_enabled = 0;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
    st.tonemap_pipeline = dev.create_render_pipeline.?(dev, &pp);
    if (st.tonemap_pipeline == c.KE_GPU_INVALID_HANDLE) {
        dev.destroy_bind_group_layout.?(dev, bgl);
        return false;
    }

    st.tonemap_bind_group = c.KE_GPU_INVALID_HANDLE;

    st.tonemap_writes = .{"backbuffer"};
    st.tonemap_reads  = .{"hdr"};
    st.tonemap_io = std.mem.zeroes(c.ke_render_pass_io);
    st.tonemap_io.writes = @ptrCast(&st.tonemap_writes);
    st.tonemap_io.writes_count = 1;
    st.tonemap_io.reads = @ptrCast(&st.tonemap_reads);
    st.tonemap_io.reads_count = 1;
    st.tonemap_io.cmd_slot = 4; // after forward (slot 3)

    st.tonemap_access = .{
        .{ .cid = st.hdr_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.core.ref.*.cid.?(st.core.ref, "backbuffer"), .access = c.KE_ACCESS_WRITE },
    };
    return true;
}

fn registerSys(rt: *c.ke_runtime, name: [*c]const u8,
               queries: [*c]const c.ke_query_decl, query_count: u32,
               access: [*c]const c.ke_component_access, access_count: u32,
               user: anytype, exec: ExecFn) void {
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
    const dev = st.device;
    if (st.tonemap_bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, st.tonemap_bind_group);
    if (st.tonemap_bgl != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group_layout.?(dev, st.tonemap_bgl);
    if (st.core.destroy) |d| d(st.core.ref);
    gpa.destroy(st);
}

const empty = c.ke_render_module_handle{ .ref = null, .destroy = null };

export fn ke_render_module_create(runtime: ?*c.ke_runtime, ecs: ?*c.ke_ecs, device: ?*c.ke_gpu_device,
                                  default_passes: c.ke_bool, logger: ?*c.ke_logger,
                                  cluster_params: ?*const c.ke_render_cluster_params,
                                  feature_params: ?*const c.ke_render_feature_params, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_module_handle {
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
    // 0 (or an absent params struct) means "use the engine default" per field —
    // a caller running a denser scene than the default sweet spot can raise
    // any of these rather than hit a hardcoded ceiling (§ no-magic-numbers).
    // Resolved here (rather than inside cluster_module.setup) because
    // ke_render_cluster_params is render_module.zig's own C ABI surface.
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
    st.cluster = ClusterModule{};
    st.shadow = ShadowModule{};
    st.shadow.enabled = if (feature_params) |p| p.enable_shadows != 0 else true;
    st.ibl_enabled = if (feature_params) |p| p.enable_ibl != 0 else true;
    st.logger = logger;
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
        if (!forwardSetup(st, e, grid_x, grid_y, grid_z, max_lights_per_cluster, out_error)) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }
        if (!tonemapSetup(st, out_error)) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }

        // UI overlay pass: loads (doesn't clear) the backbuffer tonemap just wrote,
        // so text/quads composite on top. cmd_slot 5 = after tonemap's slot 4.
        st.ui_writes = .{"backbuffer"};
        st.ui_io = std.mem.zeroes(c.ke_render_pass_io);
        st.ui_io.writes = @ptrCast(&st.ui_writes);
        st.ui_io.writes_count = 1;
        st.ui_io.cmd_slot = 5;
        st.ui_io.load = 1;
        st.ui_access = .{
            .{ .cid = bb_cid, .access = c.KE_ACCESS_WRITE },
        };

        registerSys(rt, "render.begin_frame", null, 0, &st.begin_access, st.begin_access.len, st, beginFrameSys);
        registerSys(rt, "render.clear", null, 0, &st.clear_access, st.clear_access.len, st, clearSys);
        if (st.shadow.enabled) {
            registerSys(rt, "render.shadow", null, 0, &st.shadow.access, st.shadow.access.len, &st.shadow, shadow_module.system);
        }
        registerSys(rt, "render.cull", &st.cluster.cull_queries, 3, &st.cluster.cull_access, st.cluster.cull_access.len, &st.cluster, cluster_module.system);
        registerSys(rt, "render.forward", null, 0, &st.fwd_access, st.fwd_access_count, st, forwardSys);
        registerSys(rt, "render.tonemap", null, 0, &st.tonemap_access, st.tonemap_access.len, st, tonemapSys);
        registerSys(rt, "render.ui", null, 0, &st.ui_access, st.ui_access.len, st, uiSys);
        registerSys(rt, "render.end_frame", null, 0, &st.end_access, st.end_access.len, st, endFrameSys);
    }

    return .{ .ref = @ptrCast(st), .destroy = destroyModule };
}
