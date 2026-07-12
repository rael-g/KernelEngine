const std = @import("std");
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;

// Transparent-forward pass — the other half of the deferred+forward hybrid.
// Only BLEND materials reach it (the gbuffer plugin skips them; a G-buffer
// holds one surface per pixel, so N-layer order-dependent blending cannot be
// represented there). Depth-tests LEQUAL against the G-buffer's "depth"
// without writing it, and blends into "hdr" after skybox.
//
// Shares set 0 (frame + shadow/ibl gap-filling) and set 3 (cluster light
// lists) with the deferred-lighting plugin — same shading library, same
// hooks. Adds one more: refraction_feature reads "hdr_opaque", a same-frame
// snapshot of "hdr" taken (via a raw encoder copy, before this pass's own
// render pass opens) so a refracting fragment can sample what's already been
// shaded behind it without a read/write hazard against the target it also
// writes.
//
// Owns its own material (set 1, per-mesh) + object (set 2, per-draw) binding,
// mirroring the gbuffer plugin — this pass draws real geometry, not a
// fullscreen triangle like deferred-lighting/skybox/tonemap.

const gpa = std.heap.c_allocator;

const MAX_DRAWS = 512;
const UNIFORM_STRIDE = 256; // dynamic-offset alignment (>= minUniformBufferOffsetAlignment)

// Set 2 — per-object transform. Matches forward_common.slang's PerObject.
const PerObject = extern struct {
    mvp: [16]f32,
    model: [16]f32,
};

// Matches transparent_forward.slang's PerFrame.
const PerFrame = extern struct {
    camera_pos: [4]f32,
    light_dir: [4]f32,
    light_color: [4]f32,
    ambient: [4]f32,
    shadow_params: [4]f32, // z = directional active
    viewport: [4]f32, // x=w, y=h
    view: [16]f32,
};

// Mirrors ke_directional_light_component (10 floats, see render/components.h).
const DirLight = extern struct {
    dir: [3]f32,
    rgb: [3]f32,
    intensity: f32,
    ambient: [3]f32,
};

// Mirrors the C# AmbientLightComponent { Vector3 Color } (registered "AmbientLight").
const AmbientComp = extern struct { color: [3]f32 };
// Mirrors the framework SkyboxComponent (registered "Skybox"): a cubemap handle.
const SkyboxComp = extern struct { cubemap: c.ke_texture_handle };

// One transparent draw, collected while iterating the mesh query, then sorted
// back-to-front before recording. ke_ecs has no ordered iteration (query_resolve
// returns archetype segments in storage order), so the pass builds and sorts
// its own list rather than relying on iteration order.
const Draw = struct {
    mesh: *const c.ke_mesh_component,
    transform: *const c.ke_transform_component,
    view_depth: f32,
};

fn drawFartherFirst(_: void, a: Draw, b: Draw) bool {
    return a.view_depth > b.view_depth; // back-to-front: farthest drawn first
}

const ForwardModule = struct {
    core: *c.ke_render_core = undefined,
    device: *c.ke_gpu_device = undefined,
    ndc: c.ke_ndc_convention = undefined,
    logger: ?*c.ke_logger = null,

    // When false, bindings 7-8 are forced to the engine's default black cubemap
    // regardless of any skybox — the shader still samples it, but IBL is 0.
    ibl_enabled: bool = true,

    mesh_cid: c.ke_component_id = undefined,
    transform_cid: c.ke_component_id = undefined,
    camera_cid: c.ke_component_id = undefined,
    light_cid: c.ke_component_id = undefined,
    ambient_cid: c.ke_component_id = undefined,
    skybox_cid: c.ke_component_id = undefined,

    // Not a resolved handle — re-queried via core.get_or_create_pipeline every
    // record() call. §6 Mechanism 1 upgrades a fresh miss's magenta fallback
    // to the real compiled PSO asynchronously; a handle cached once at setup
    // would freeze on whichever one was current AT setup time (the fallback,
    // since the real compile hasn't finished yet) and never see the upgrade.
    pipeline_params: c.ke_gpu_render_pipeline_params = undefined,
    frame_bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE, // set 0
    frame_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE, // set 0, rebuilt on env change
    frame_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    obj_bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE, // set 2
    obj_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    obj_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    env_cubemap: c.ke_texture_handle = .{ .bits = c.KE_HANDLE_NONE },

    draws: [MAX_DRAWS]Draw = undefined,

    writes: [2][*c]const u8 = undefined, // hdr (blend), depth (LEQUAL test, no write)
    reads: [1][*c]const u8 = undefined, // shadow_map (conditional)
    io: c.ke_render_pass_io = undefined,
    // WRITE hdr, hdr_opaque (2) + READ depth, mesh, transform, camera, light,
    // ambient, skybox, frame_cid, cluster_lights (9) + 1 conditional
    // (shadow_map) = 12 max.
    access: [12]c.ke_component_access = undefined,
    access_count: u32 = 0,
    // Resolved single-threaded by the runtime before the wave dispatches; the
    // body then reads plain memory via ke_system_ctx_view and touches the ECS
    // not at all.
    queries: [5]c.ke_query_decl = undefined, // [camera,transform], [skybox], [dir_light], [ambient], [mesh,transform]
};

fn makePerspective(ndc: c.ke_ndc_convention, fovy: f32, aspect: f32, near: f32, far: f32) zm.Mat {
    var p = if (ndc.z_zero_to_one != 0)
        zm.perspectiveFovLh(fovy, aspect, near, far)
    else
        zm.perspectiveFovLhGl(fovy, aspect, near, far);
    if (ndc.y_flip != 0) p[1][1] = -p[1][1];
    return p;
}

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
    var ev = c.ke_log_event{ .level = c.KE_LOG_LEVEL_ERROR, .tag = "render_forward", .message = msg.ptr };
    lg.log.?(lg, &ev);
}

inline fn moduleOf(user: ?*anyopaque) *ForwardModule {
    return @alignCast(@ptrCast(user.?));
}

// Set 0 — frame UBO + refraction source (1-2) + shadow (4-6) + ibl (7-8). The
// refraction/shadow/ibl bindings are stable views set once here (and whenever
// the bound environment changes), not per-frame transient ones — unlike the
// deferred-lighting plugin's set-1 gbuffer bind group, nothing here changes
// size or identity across frames.
fn rebuildFrameBindGroup(fwd: *ForwardModule) void {
    const dev = fwd.device;
    const core = fwd.core;
    const env_view = core.*.texture_view.?(core, fwd.env_cubemap);
    const white_view = core.*.texture_view.?(core, core.*.white_texture.?(core));
    const black_cube_view = core.*.texture_view.?(core, .{ .bits = c.KE_HANDLE_NONE });
    const hdr_opaque_view = core.*.resource_view.?(core, "hdr_opaque");
    const smp = core.*.sampler.?(core);

    // Shadow's outputs are looked up by name, not through a pointer to the
    // shadow plugin — an invalid view IS the "off" signal (see the
    // deferred-lighting plugin for the same pattern).
    const shadow_view_raw = core.*.resource_view.?(core, "shadow_map");
    const shadow_tex_view = if (shadow_view_raw != c.KE_GPU_INVALID_HANDLE) shadow_view_raw else white_view;
    const shadow_lvp_buf = core.*.resource_buffer.?(core, "shadow_lvp");
    const shadow_lvp_size = core.*.resource_buffer_size.?(core, "shadow_lvp");
    const ibl_view = if (fwd.ibl_enabled) env_view else black_cube_view;

    const entries = [8]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = fwd.frame_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(PerFrame), .texture_view = 0, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = hdr_opaque_view, .sampler = 0 },
        .{ .binding = 2, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
        .{ .binding = 4, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = shadow_lvp_buf, .buffer_offset = 0, .buffer_size = shadow_lvp_size, .texture_view = 0, .sampler = 0 },
        .{ .binding = 5, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = shadow_tex_view, .sampler = 0 },
        .{ .binding = 6, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
        .{ .binding = 7, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = ibl_view, .sampler = 0 },
        .{ .binding = 8, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
    };

    var err: ?*c.ke_error = null;
    fwd.frame_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = fwd.frame_bgl,
        .entry_count = 8,
        .entries = &entries,
    }, &err);
    if (err != null) logGpuError(fwd.logger, err, "transparent-forward frame bind group");
}

fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const fwd = moduleOf(user);
    const core = fwd.core;

    // View 0 = [camera, transform]; the first match is the active camera.
    var cam_segc: usize = 0;
    const cam_segs = c.ke_system_ctx_view(ctx, 0, &cam_segc);
    // No camera: deferred-lighting already cleared/shaded hdr (or left it
    // cleared); this pass composites on top, so there is nothing to do.
    if (cam_segc == 0 or cam_segs[0].count == 0) return;

    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_segs[0].columns[0]));
    const cam_tc: *const c.ke_transform_component = @ptrCast(@alignCast(cam_segs[0].columns[1]));

    const pc = core.*.begin_pass.?(core, ctx, &fwd.io);
    if (pc == null) return;

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);

    // Snapshot "hdr" into "hdr_opaque" before this pass's own render pass opens
    // (a copy cannot be issued once a render pass is active) — the refraction
    // hook samples this, never the target this pass is itself writing into.
    const enc = pc.*.encoder.?(pc);
    const hdr_tex = core.*.resource_texture.?(core, "hdr");
    const hdr_opaque_tex = core.*.resource_texture.?(core, "hdr_opaque");
    enc.*.copy_texture_to_texture.?(enc, hdr_tex, hdr_opaque_tex, bw, bh);

    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;
    const view = cameraView(cam_tc);
    const fov_rad = cam.fov * @as(f32, std.math.pi / 180.0);
    const proj = makePerspective(fwd.ndc, fov_rad, aspect, cam.near_plane, cam.far_plane);
    const view_proj = zm.mul(view, proj);

    // Environment cubemap from the first skybox entity (default black otherwise);
    // rebuild set 0 only when the bound environment changes. View 1 = [skybox].
    var sky_segc: usize = 0;
    const sky_segs = c.ke_system_ctx_view(ctx, 1, &sky_segc);
    const want_env: c.ke_texture_handle = if (sky_segc != 0 and sky_segs[0].count != 0)
        (@as(*const SkyboxComp, @ptrCast(@alignCast(sky_segs[0].columns[0])))).cubemap
    else
        .{ .bits = c.KE_HANDLE_NONE };
    if (want_env.bits != fwd.env_cubemap.bits or fwd.frame_bind_group == c.KE_GPU_INVALID_HANDLE) {
        fwd.env_cubemap = want_env;
        rebuildFrameBindGroup(fwd);
    }

    var frame: PerFrame = .{
        .camera_pos = .{ cam_tc.position.x, cam_tc.position.y, cam_tc.position.z, 1.0 },
        .light_dir = .{ -0.4, -1.0, -0.3, 0.0 },
        .light_color = .{ 1.0, 1.0, 1.0, 1.0 },
        .ambient = .{ 0.0, 0.0, 0.0, 0.0 },
        .shadow_params = .{ 0.0, 0.0, 0.0, 0.0 },
        .viewport = .{ @floatFromInt(bw), @floatFromInt(bh), 0.0, 0.0 },
        .view = undefined,
    };
    zm.storeMat(frame.view[0..], view);

    // View 2 = [directional_light]; present → enable the directional term and
    // seed the scene ambient from it.
    var li_segc: usize = 0;
    const li_segs = c.ke_system_ctx_view(ctx, 2, &li_segc);
    if (li_segc != 0 and li_segs[0].count != 0) {
        const d: *const DirLight = @ptrCast(@alignCast(li_segs[0].columns[0]));
        frame.light_dir = .{ d.dir[0], d.dir[1], d.dir[2], 0.0 };
        frame.light_color = .{ d.rgb[0], d.rgb[1], d.rgb[2], d.intensity };
        frame.ambient = .{ d.ambient[0], d.ambient[1], d.ambient[2], 0.0 };
        frame.shadow_params[2] = 1.0;
    }
    // View 3 = [AmbientLight]; a standalone ambient overrides the directional's.
    var am_segc: usize = 0;
    const am_segs = c.ke_system_ctx_view(ctx, 3, &am_segc);
    if (am_segc != 0 and am_segs[0].count != 0) {
        const al: *const AmbientComp = @ptrCast(@alignCast(am_segs[0].columns[0]));
        frame.ambient = .{ al.color[0], al.color[1], al.color[2], 0.0 };
    }
    core.*.upload.?(core, fwd.frame_uniform, 0, &frame, @sizeOf(PerFrame));

    // View 4 = [mesh, transform]. Collect only BLEND materials — the gbuffer
    // plugin already drew everything else. Compute each draw's view-space
    // depth so they can be sorted back-to-front before recording (blending is
    // not commutative; ke_ecs has no ordered iteration to rely on instead).
    var draw_count: u32 = 0;
    var segc: usize = 0;
    const segs = c.ke_system_ctx_view(ctx, 4, &segc);
    var s: usize = 0;
    while (s < segc and draw_count < MAX_DRAWS) : (s += 1) {
        const meshes: [*c]const c.ke_mesh_component = @ptrCast(@alignCast(segs[s].columns[0]));
        const tcs: [*c]const c.ke_transform_component = @ptrCast(@alignCast(segs[s].columns[1]));
        var i: usize = 0;
        while (i < segs[s].count and draw_count < MAX_DRAWS) : (i += 1) {
            if (core.*.material_alpha_mode.?(core, meshes[i].material) != c.KE_ALPHA_MODE_BLEND) continue;
            const wp = zm.f32x4(tcs[i].position.x, tcs[i].position.y, tcs[i].position.z, 1.0);
            const view_pos = zm.mul(wp, view);
            fwd.draws[draw_count] = .{ .mesh = @ptrCast(&meshes[i]), .transform = @ptrCast(&tcs[i]), .view_depth = view_pos[2] };
            draw_count += 1;
        }
    }
    std.sort.pdq(Draw, fwd.draws[0..draw_count], {}, drawFartherFirst);

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &fwd.pipeline_params));
    rp.*.set_bind_group.?(rp, 0, fwd.frame_bind_group, null, 0);
    rp.*.set_bind_group.?(rp, 3, core.*.resource_bind_group.?(core, "cluster_lights"), null, 0);

    var d: u32 = 0;
    while (d < draw_count) : (d += 1) {
        const draw = fwd.draws[d];
        var vbo: c.ke_gpu_buffer = 0;
        var ibo: c.ke_gpu_buffer = 0;
        var idx_count: u32 = 0;
        if (core.*.mesh_buffers.?(core, draw.mesh.mesh, &vbo, &ibo, &idx_count) == 0) continue;

        const model = zm.loadMat(draw.transform.world_matrix.m[0..]);
        const mvp = zm.mul(model, view_proj);
        var u: PerObject = undefined;
        zm.storeMat(u.mvp[0..], mvp);
        zm.storeMat(u.model[0..], model);
        const offset: u32 = d * UNIFORM_STRIDE;
        core.*.upload.?(core, fwd.obj_uniform, offset, &u, @sizeOf(PerObject));

        const mat_bg = core.*.material_bind_group.?(core, draw.mesh.material);
        rp.*.set_bind_group.?(rp, 1, mat_bg, null, 0); // set 1: per-material
        rp.*.set_bind_group.?(rp, 2, fwd.obj_bind_group, &offset, 1); // set 2: per-object
        rp.*.set_vertex_buffer.?(rp, 0, vbo, 0);
        rp.*.set_index_buffer.?(rp, ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.*.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
    }
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

fn setup(fwd: *ForwardModule, dev: *c.ke_gpu_device, core: *c.ke_render_core,
         ndc: c.ke_ndc_convention, logger: ?*c.ke_logger, ibl_enabled: bool,
         mesh_cid: c.ke_component_id, transform_cid: c.ke_component_id, camera_cid: c.ke_component_id,
         light_cid: c.ke_component_id, ambient_cid: c.ke_component_id, skybox_cid: c.ke_component_id,
         frame_cid: c.ke_component_id,
         out_error: [*c][*c]c.ke_error) bool {
    fwd.core = core;
    fwd.device = dev;
    fwd.ndc = ndc;
    fwd.logger = logger;
    fwd.ibl_enabled = ibl_enabled;
    fwd.mesh_cid = mesh_cid;
    fwd.transform_cid = transform_cid;
    fwd.camera_cid = camera_cid;
    fwd.light_cid = light_cid;
    fwd.ambient_cid = ambient_cid;
    fwd.skybox_cid = skybox_cid;
    fwd.env_cubemap = .{ .bits = c.KE_HANDLE_NONE };

    const frag = c.KE_GPU_SHADER_STAGE_FRAGMENT;
    const frame_bgl_entries = [_]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 1, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 2, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 4, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 5, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 6, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 7, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = c.KE_GPU_TEXTURE_DIM_CUBE },
        .{ .binding = 8, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    fwd.frame_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 8,
        .entries = &frame_bgl_entries,
    });

    // Set 2 — per-object transform ring (dynamic offset, vertex stage). Same
    // shape as the gbuffer plugin's.
    const obj_bgl_entry = c.ke_gpu_bind_group_layout_entry{
        .binding = 0,
        .visibility = c.KE_GPU_SHADER_STAGE_VERTEX,
        .type = c.KE_GPU_BINDING_TYPE_BUFFER,
        .has_dynamic_offset = 1,
        .view_dimension = 0,
    };
    fwd.obj_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 1,
        .entries = &obj_bgl_entry,
    });

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

    // Neither the path nor the shader format is named here — core.load_shader
    // resolves both. The core owns the result; this pass never destroys it.
    const vs = core.*.load_shader.?(core, "forward", c.KE_GPU_SHADER_STAGE_VERTEX, out_error);
    if (vs == c.KE_GPU_INVALID_HANDLE) return false;
    const fs = core.*.load_shader.?(core, "forward", c.KE_GPU_SHADER_STAGE_FRAGMENT, out_error);
    if (fs == c.KE_GPU_INVALID_HANDLE) return false;

    var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    pp.vertex_module = vs;
    pp.fragment_module = fs;
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    pp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    pp.vertex_buffer_count = 1;
    pp.vertex_buffers = &vbl;
    // Standard alpha blend: the surface's own alpha weighs its shading against
    // whatever is already in "hdr" (skybox + opaque, composited by deferred-
    // lighting + skybox before this pass runs).
    pp.blend_state.blend_enabled = 1;
    pp.blend_state.src_color = c.KE_GPU_BLEND_FACTOR_SRC_ALPHA;
    pp.blend_state.dst_color = c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.color_op = c.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.src_alpha = c.KE_GPU_BLEND_FACTOR_ONE;
    pp.blend_state.dst_alpha = c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.alpha_op = c.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.write_mask = 0x0F;
    // LEQUAL, no write: tests against the G-buffer's depth (already populated
    // by the gbuffer plugin) without occluding surfaces this pass draws later
    // — depth ordering among transparents is handled by the back-to-front
    // sort, not by the depth buffer.
    pp.depth_stencil.depth_test_enabled = 1;
    pp.depth_stencil.depth_write_enabled = 0;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_LESS_EQUAL;
    pp.bind_group_layouts[0] = fwd.frame_bgl;
    pp.bind_group_layouts[1] = core.*.material_layout.?(core); // set 1: per-material
    pp.bind_group_layouts[2] = fwd.obj_bgl; // set 2: per-object
    pp.bind_group_layouts[3] = core.*.resource_bind_group_layout.?(core, "cluster_lights"); // set 3: cluster light lists
    pp.bind_group_layout_count = 4;
    pp.color_target_formats[0] = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT; // HDR
    pp.color_target_count = 1;
    fwd.pipeline_params = pp;
    if (core.*.get_or_create_pipeline.?(core, &fwd.pipeline_params) == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "transparent-forward: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    fwd.frame_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = @sizeOf(PerFrame),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (fwd.frame_uniform == c.KE_GPU_INVALID_HANDLE) return false;

    fwd.obj_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = UNIFORM_STRIDE * MAX_DRAWS,
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (fwd.obj_uniform == c.KE_GPU_INVALID_HANDLE) return false;
    const obj_bg_entry = c.ke_gpu_bind_group_entry{
        .binding = 0,
        .type = c.KE_GPU_BINDING_TYPE_BUFFER,
        .buffer = fwd.obj_uniform,
        .buffer_offset = 0,
        .buffer_size = @sizeOf(PerObject),
        .texture_view = 0,
        .sampler = 0,
    };
    fwd.obj_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = fwd.obj_bgl,
        .entry_count = 1,
        .entries = &obj_bg_entry,
    }, out_error);
    if (fwd.obj_bind_group == c.KE_GPU_INVALID_HANDLE) return false;

    // Snapshot target for refraction_feature.slang — same format/sizing as
    // "hdr" (declared by the deferred-lighting plugin), copied afresh each frame.
    const hdr_opaque_cid = core.*.declare.?(core, &c.ke_render_resource_desc{
        .name = "hdr_opaque",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT,
        .width = 0, .height = 0, .scale_x = 1.0, .scale_y = 1.0,
    }, out_error);

    rebuildFrameBindGroup(fwd);

    // Shadow's presence is read from the named-resource table, not a pointer
    // to the shadow plugin (see the deferred-lighting plugin for the same
    // pattern).
    const shadow_map_cid = core.*.cid.?(core, "shadow_map");
    const shadow_enabled = shadow_map_cid != c.KE_COMPONENT_INVALID;
    // "light_clusters" (not "cluster_lights") is the scheduling ordering tag —
    // cull WRITEs it, this pass READs it; the actual light data crosses
    // through the "cluster_lights" bind group looked up separately below.
    const cluster_lights_cid = core.*.cid.?(core, "light_clusters");

    // "hdr" LOADs (composites over skybox's output); "depth" also LOADs, tested
    // read-only (io.load governs both — see pass_recording.zig's ctxBeginRender).
    fwd.writes = .{ "hdr", "depth" };
    fwd.reads = .{"shadow_map"};
    fwd.io = std.mem.zeroes(c.ke_render_pass_io);
    fwd.io.writes = @ptrCast(&fwd.writes);
    fwd.io.writes_count = 2;
    fwd.io.reads = @ptrCast(&fwd.reads);
    fwd.io.reads_count = if (shadow_enabled) 1 else 0;
    fwd.io.load = 1;
    fwd.io.cmd_slot = 6; // after skybox (5), before tonemap (7)

    var ac: u32 = 0;
    fwd.access[ac] = .{ .cid = core.*.cid.?(core, "hdr"), .access = c.KE_ACCESS_WRITE };
    ac += 1;
    fwd.access[ac] = .{ .cid = hdr_opaque_cid, .access = c.KE_ACCESS_WRITE };
    ac += 1;
    // READ, not WRITE: this pass tests depth but never writes it (depth_write_enabled=0).
    fwd.access[ac] = .{ .cid = core.*.cid.?(core, "depth"), .access = c.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = mesh_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = transform_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = camera_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = light_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = ambient_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = skybox_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = frame_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = cluster_lights_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    if (shadow_enabled) {
        fwd.access[ac] = .{ .cid = shadow_map_cid, .access = c.KE_ACCESS_READ };
        ac += 1;
    }
    fwd.access_count = ac;

    const rd = c.KE_ACCESS_READ;
    fwd.queries = std.mem.zeroes([5]c.ke_query_decl);
    fwd.queries[0].terms[0] = .{ .cid = camera_cid, .access = rd };
    fwd.queries[0].terms[1] = .{ .cid = transform_cid, .access = rd };
    fwd.queries[0].term_count = 2;
    fwd.queries[1].terms[0] = .{ .cid = skybox_cid, .access = rd };
    fwd.queries[1].term_count = 1;
    fwd.queries[2].terms[0] = .{ .cid = light_cid, .access = rd };
    fwd.queries[2].term_count = 1;
    fwd.queries[3].terms[0] = .{ .cid = ambient_cid, .access = rd };
    fwd.queries[3].term_count = 1;
    fwd.queries[4].terms[0] = .{ .cid = mesh_cid, .access = rd };
    fwd.queries[4].terms[1] = .{ .cid = transform_cid, .access = rd };
    fwd.queries[4].term_count = 2;
    return true;
}

fn destroyHandle(self: ?*c.ke_render_forward) callconv(.c) void {
    const fwd: *ForwardModule = @ptrCast(@alignCast(self orelse return));
    const dev = fwd.device;
    if (fwd.frame_bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, fwd.frame_bind_group);
    gpa.destroy(fwd);
}

export fn ke_render_forward_create(runtime: ?*c.ke_runtime, core: ?*c.ke_render_core,
                                    device: ?*c.ke_gpu_device, ndc: c.ke_ndc_convention,
                                    logger: ?*c.ke_logger, ibl_enabled: c.ke_bool,
                                    mesh_cid: c.ke_component_id, transform_cid: c.ke_component_id,
                                    camera_cid: c.ke_component_id, light_cid: c.ke_component_id,
                                    ambient_cid: c.ke_component_id, skybox_cid: c.ke_component_id,
                                    frame_cid: c.ke_component_id,
                                    out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_forward_handle {
    const empty = c.ke_render_forward_handle{ .ref = null, .destroy = null };
    const rt = runtime orelse return empty;
    const core_ref = core orelse return empty;
    const dev = device orelse return empty;

    const fwd = gpa.create(ForwardModule) catch return empty;
    fwd.* = .{};
    if (!setup(fwd, dev, core_ref, ndc, logger, ibl_enabled != 0,
               mesh_cid, transform_cid, camera_cid, light_cid, ambient_cid, skybox_cid, frame_cid, out_error))
    {
        gpa.destroy(fwd);
        return empty;
    }

    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = "render.forward_transparent";
    params.phase = c.KE_PHASE_RENDER;
    params.queries = &fwd.queries;
    params.query_count = fwd.queries.len;
    params.access_list = &fwd.access;
    params.access_count = fwd.access_count;
    params.pinned_thread = 0;
    params.user_data = fwd;
    params.execute = system;
    _ = rt.register_system.?(rt, &params, null);

    return .{ .ref = @ptrCast(fwd), .destroy = destroyHandle };
}
