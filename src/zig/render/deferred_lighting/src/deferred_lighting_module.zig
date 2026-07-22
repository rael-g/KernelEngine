const std = @import("std");

// dlopen'd by a foreign (non-Zig) host (the C# runtime) alongside many other
// plugins in one process. std.Thread's default 256 KiB threadlocal signal
// stack blows the small glibc static-TLS surplus once enough accumulate
// (verified: "cannot allocate memory in static TLS block"); the extra crash-
// handler stack trace it buys isn't worth an unloadable plugin.
pub const std_options: std.Options = .{ .signal_stack_size = null };
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;

// Deferred lighting pass — the opaque path's second half. Fullscreen triangle
// that reads the G-buffer (gbuffer plugin wrote it) + depth, reconstructs world
// position, and shades with the shared hooks (shadow/cluster/ibl + ke.pbr).
// Those are the same functions the forward pass calls: the shading library does
// not care whether it runs inside a mesh fragment or a fullscreen dispatch.
// Writes "hdr", which tonemap reads.
//
// Bind groups mirror what the shared feature shaders require:
//   set 0: frame UBO (0) + shadow (4,5,6) + ibl (7,8)   — same layout as forward
//   set 1: the 3 G-buffer targets + depth (texel-fetched, no sampler)
//   set 2: empty (the features leave set 2 unused; the positional array needs it)
//   set 3: cluster light lists — same as forward
// Shadow's and cluster's outputs (LVP uniform, shadow view, light-list bind
// group + layout) are looked up by name through the borrowed ke_render_core —
// this plugin never holds a pointer to the shadow/cluster plugins. Owns the
// env-cubemap tracking its IBL sampling needs (rebuilding set 0 when the
// environment changes).

const gpa = std.heap.c_allocator;

// Matches deferred_lighting.slang's DeferredFrame (std140).
const DeferredFrame = extern struct {
    camera_pos: [4]f32,
    light_dir: [4]f32,
    light_color: [4]f32,
    ambient: [4]f32,
    shadow_params: [4]f32, // z = directional active
    viewport: [4]f32, // x=w, y=h
    view: [16]f32,
    inv_view_proj: [16]f32,
};


const DeferredLightingModule = struct {
    core: *c.ke_render_core = undefined,
    device: *c.ke_gpu_device = undefined,
    ndc: c.ke_ndc_convention = undefined,
    logger: ?*c.ke_logger = null,
    ibl_enabled: bool = true,

    camera_cid: c.ke_component_id = undefined,
    transform_cid: c.ke_component_id = undefined,
    light_cid: c.ke_component_id = undefined,
    ambient_cid: c.ke_component_id = undefined,
    skybox_cid: c.ke_component_id = undefined,

    // Re-queried via core.get_or_create_pipeline every record() call — see
    // forward_module.zig's ForwardModule.pipeline_params for why a handle
    // cached once at setup can't observe the async real-PSO upgrade.
    pipeline_params: c.ke_gpu_render_pipeline_params = undefined,
    frame_bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE, // set 0
    gbuf_bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE, // set 1
    empty_bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE, // set 2 (unused)
    empty_bg: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    frame_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    frame_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE, // set 0, rebuilt on env change
    gbuf_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE, // set 1, rebuilt per frame (transient views)
    env_cubemap: c.ke_texture_handle = .{ .bits = c.KE_HANDLE_NONE },

    reads: [6][*c]const u8 = undefined,
    writes: [1][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
    // 5 unconditional (hdr write; albedo/normal/emissive/depth read) + 1
    // conditional (shadow_map) + 7 unconditional (cluster/camera/transform/
    // light/ambient/skybox/frame) = 13 max.
    access: [13]c.ke_component_access = undefined,
    // Resolved single-threaded by the runtime before the wave dispatches; the
    // body then reads plain memory via ke_system_ctx_view and touches the ECS
    // not at all.
    queries: [4]c.ke_query_decl = undefined, // [camera,transform], [skybox], [dir_light], [ambient]
    access_count: u32 = 0,
};

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
    // Reflect view-space X so world +X reads to the right — same convention as
    // the forward pass's camera view, keeping the deferred path aligned.
    return zm.mul(view, zm.scaling(-1.0, 1.0, 1.0));
}

fn makePerspective(ndc: c.ke_ndc_convention, fovy: f32, aspect: f32, near: f32, far: f32) zm.Mat {
    var p = if (ndc.z_zero_to_one != 0)
        zm.perspectiveFovLh(fovy, aspect, near, far)
    else
        zm.perspectiveFovLhGl(fovy, aspect, near, far);
    if (ndc.y_flip != 0) p[1][1] = -p[1][1];
    return p;
}

fn logGpuError(logger: ?*c.ke_logger, err: ?*c.ke_error, what: []const u8) void {
    const lg = logger orelse return;
    const e = err orelse return;
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "{s} failed: {s}", .{ what, e.message }) catch return;
    var ev = c.ke_log_event{ .level = c.KE_LOG_LEVEL_ERROR, .tag = "render_deferred_lighting", .message = msg.ptr };
    lg.log.?(lg, &ev);
}

inline fn moduleOf(user: ?*anyopaque) *DeferredLightingModule {
    return @alignCast(@ptrCast(user.?));
}

// Set 0 — frame UBO + shadow (4,5,6) + ibl (7,8). Same shape as forward's set 0
// so the shared shadow_feature/ibl_feature bindings resolve. Rebuilt only when
// the bound environment cubemap changes (rare — scene load).
fn rebuildFrameBindGroup(dl: *DeferredLightingModule) void {
    const dev = dl.device;
    const core = dl.core;
    const env_view = core.*.texture_view.?(core, dl.env_cubemap);
    const white_view = core.*.texture_view.?(core, core.*.white_texture.?(core)); // 1x1 white
    const black_cube_view = core.*.texture_view.?(core, .{ .bits = c.KE_HANDLE_NONE }); // black cube
    const smp = core.*.sampler.?(core);

    // Shadow's outputs are looked up by name, not through a pointer to the
    // shadow plugin — resource_view returns KE_GPU_INVALID_HANDLE when shadow
    // is disabled (it never declares "shadow_map" in that case), which is the
    // signal to fall back to the neutral white texture.
    const shadow_view_raw = core.*.resource_view.?(core, "shadow_map");
    const shadow_tex_view = if (shadow_view_raw != c.KE_GPU_INVALID_HANDLE) shadow_view_raw else white_view;
    const shadow_lvp_buf = core.*.resource_buffer.?(core, "shadow_lvp");
    const shadow_lvp_size = core.*.resource_buffer_size.?(core, "shadow_lvp");
    const ibl_view = if (dl.ibl_enabled) env_view else black_cube_view;

    const entries = [6]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = dl.frame_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(DeferredFrame), .texture_view = 0, .sampler = 0 },
        .{ .binding = 4, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = shadow_lvp_buf, .buffer_offset = 0, .buffer_size = shadow_lvp_size, .texture_view = 0, .sampler = 0 },
        .{ .binding = 5, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = shadow_tex_view, .sampler = 0 },
        .{ .binding = 6, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
        .{ .binding = 7, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = ibl_view, .sampler = 0 },
        .{ .binding = 8, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
    };
    var err: ?*c.ke_error = null;
    dl.frame_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = dl.frame_bgl,
        .entry_count = 6,
        .entries = &entries,
    }, &err);
    if (err != null) logGpuError(dl.logger, err, "deferred frame bind group");
}

fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const dl = moduleOf(user);
    const core = dl.core;
    const dev = dl.device;

    // View 0 = [camera, transform]; the first match is the active camera.
    var cam_segc: usize = 0;
    const cam_segs = c.ke_system_ctx_view(ctx, 0, &cam_segc);

    const pc = core.*.begin_pass.?(core, ctx, &dl.io);
    if (pc == null) return;
    if (cam_segc == 0 or cam_segs[0].count == 0) {
        const rp0 = pc.*.begin_render.?(pc);
        rp0.*.end.?(rp0);
        core.*.end_pass.?(core, pc);
        return;
    }
    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_segs[0].columns[0]));
    const cam_tc: *const c.ke_transform_component = @ptrCast(@alignCast(cam_segs[0].columns[1]));

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    const view = cameraView(cam_tc);
    const fov_rad = cam.fov * @as(f32, std.math.pi / 180.0);
    const proj = makePerspective(dl.ndc, fov_rad, aspect, cam.near_plane, cam.far_plane);
    const view_proj = zm.mul(view, proj);
    const inv_vp = zm.inverse(view_proj);

    // Environment cubemap from the first skybox entity (default black otherwise);
    // rebuild set 0 only when the bound environment changes. View 1 = [skybox].
    var sky_segc: usize = 0;
    const sky_segs = c.ke_system_ctx_view(ctx, 1, &sky_segc);
    const want_env: c.ke_texture_handle = if (sky_segc != 0 and sky_segs[0].count != 0)
        (@as(*const c.ke_skybox_component, @ptrCast(@alignCast(sky_segs[0].columns[0])))).cubemap
    else
        .{ .bits = c.KE_HANDLE_NONE };
    if (want_env.bits != dl.env_cubemap.bits) {
        dl.env_cubemap = want_env;
        rebuildFrameBindGroup(dl);
    }

    // Per-frame UBO: camera + directional light + ambient + matrices.
    var frame: DeferredFrame = .{
        .camera_pos = .{ cam_tc.position.x, cam_tc.position.y, cam_tc.position.z, 1.0 },
        // Zero until a directional_light entity supplies the real values; the
        // shader ignores these while shadow_params.z stays clear.
        .light_dir = .{ 0.0, 0.0, 0.0, 0.0 },
        .light_color = .{ 0.0, 0.0, 0.0, 0.0 },
        .ambient = .{ 0.0, 0.0, 0.0, 0.0 },
        .shadow_params = .{ 0.0, 0.0, 0.0, 0.0 },
        .viewport = .{ @floatFromInt(bw), @floatFromInt(bh), 0.0, 0.0 },
        .view = undefined,
        .inv_view_proj = undefined,
    };
    zm.storeMat(frame.view[0..], view);
    zm.storeMat(frame.inv_view_proj[0..], inv_vp);

    // View 2 = [directional_light]; present → enable the directional term and
    // seed the scene ambient from it.
    var li_segc: usize = 0;
    const li_segs = c.ke_system_ctx_view(ctx, 2, &li_segc);
    if (li_segc != 0 and li_segs[0].count != 0) {
        const d: *const c.ke_directional_light_component = @ptrCast(@alignCast(li_segs[0].columns[0]));
        frame.light_dir = .{ d.dir_x, d.dir_y, d.dir_z, 0.0 };
        frame.light_color = .{ d.r, d.g, d.b, d.intensity };
        frame.ambient = .{ d.ambient_r, d.ambient_g, d.ambient_b, 0.0 };
        frame.shadow_params[2] = 1.0; // directional active
    }
    // View 3 = [AmbientLight]; a standalone ambient overrides the directional's.
    var am_segc: usize = 0;
    const am_segs = c.ke_system_ctx_view(ctx, 3, &am_segc);
    if (am_segc != 0 and am_segs[0].count != 0) {
        const al: *const c.ke_ambient_light_component = @ptrCast(@alignCast(am_segs[0].columns[0]));
        frame.ambient = .{ al.r, al.g, al.b, 0.0 };
    }
    core.*.upload.?(core, dl.frame_uniform, 0, &frame, @sizeOf(DeferredFrame));

    // Set 1 — resolve this frame's G-buffer + depth views and rebuild (transient
    // views can change on resize; same per-frame pattern tonemap uses for "hdr").
    const albedo_view = pc.*.read.?(pc, "gbuffer_albedo");
    const normal_view = pc.*.read.?(pc, "gbuffer_normal");
    const emissive_view = pc.*.read.?(pc, "gbuffer_emissive");
    const depth_view = pc.*.read.?(pc, "depth");
    const gbuf_entries = [4]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = albedo_view, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = normal_view, .sampler = 0 },
        .{ .binding = 2, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = emissive_view, .sampler = 0 },
        .{ .binding = 3, .type = c.KE_GPU_BINDING_TYPE_DEPTH_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = depth_view, .sampler = 0 },
    };
    if (dl.gbuf_bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, dl.gbuf_bind_group);
    var err: ?*c.ke_error = null;
    dl.gbuf_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = dl.gbuf_bgl,
        .entry_count = 4,
        .entries = &gbuf_entries,
    }, &err);
    if (err != null) logGpuError(dl.logger, err, "deferred gbuffer bind group");

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &dl.pipeline_params));
    rp.*.set_bind_group.?(rp, 0, dl.frame_bind_group, null, 0);
    rp.*.set_bind_group.?(rp, 1, dl.gbuf_bind_group, null, 0);
    rp.*.set_bind_group.?(rp, 2, dl.empty_bg, null, 0);
    rp.*.set_bind_group.?(rp, 3, core.*.resource_bind_group.?(core, "cluster_lights"), null, 0);
    rp.*.draw.?(rp, 3, 1, 0, 0); // fullscreen triangle
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

fn setup(dl: *DeferredLightingModule, dev: *c.ke_gpu_device, core: *c.ke_render_core,
         ndc: c.ke_ndc_convention, logger: ?*c.ke_logger, ibl_enabled: bool,
         camera_cid: c.ke_component_id, transform_cid: c.ke_component_id, light_cid: c.ke_component_id,
         ambient_cid: c.ke_component_id, skybox_cid: c.ke_component_id, frame_cid: c.ke_component_id,
         out_error: [*c][*c]c.ke_error) bool {
    dl.core = core;
    dl.device = dev;
    dl.ndc = ndc;
    dl.logger = logger;
    dl.ibl_enabled = ibl_enabled;
    dl.camera_cid = camera_cid;
    dl.transform_cid = transform_cid;
    dl.light_cid = light_cid;
    dl.ambient_cid = ambient_cid;
    dl.skybox_cid = skybox_cid;
    dl.env_cubemap = .{ .bits = c.KE_HANDLE_NONE };

    const frag = c.KE_GPU_SHADER_STAGE_FRAGMENT;
    // Set 0 layout — frame UBO (0) + shadow (4,5,6) + ibl (7,8). Bindings 1-3
    // are unused by the deferred shader (it declares none), so they are omitted;
    // gaps in binding numbers are allowed.
    const frame_bgl_entries = [_]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 4, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 5, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 6, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 7, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = c.KE_GPU_TEXTURE_DIM_CUBE },
        .{ .binding = 8, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    dl.frame_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 6,
        .entries = &frame_bgl_entries,
    });

    // Set 1 layout — the 3 G-buffer targets (unfilterable-ish float, texel-fetched)
    // + depth (unfilterable float). No sampler (Load only).
    const gbuf_bgl_entries = [_]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 1, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 2, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 3, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_DEPTH_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    dl.gbuf_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 4,
        .entries = &gbuf_bgl_entries,
    });

    // Set 2 — empty (features use 0 and 3; the positional array needs 2 filled).
    dl.empty_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 0,
        .entries = null,
    });
    dl.empty_bg = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = dl.empty_bgl,
        .entry_count = 0,
        .entries = null,
    }, out_error);
    if (dl.empty_bg == c.KE_GPU_INVALID_HANDLE) return false;

    // Neither the path nor the shader format is named here — core.load_shader
    // resolves both. The core owns the result; this pass never destroys it.
    const vs = core.*.load_shader.?(core, "deferred_lighting", c.KE_GPU_SHADER_STAGE_VERTEX, out_error);
    if (vs == c.KE_GPU_INVALID_HANDLE) return false;
    const fs = core.*.load_shader.?(core, "deferred_lighting", c.KE_GPU_SHADER_STAGE_FRAGMENT, out_error);
    if (fs == c.KE_GPU_INVALID_HANDLE) return false;

    var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    pp.vertex_module = vs;
    pp.fragment_module = fs;
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    pp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = 0; // fullscreen resolve, no depth
    pp.depth_stencil.depth_write_enabled = 0;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
    pp.bind_group_layouts[0] = dl.frame_bgl;
    pp.bind_group_layouts[1] = dl.gbuf_bgl;
    pp.bind_group_layouts[2] = dl.empty_bgl;
    pp.bind_group_layouts[3] = core.*.resource_bind_group_layout.?(core, "cluster_lights"); // set 3: cluster light lists
    pp.bind_group_layout_count = 4;
    pp.color_target_formats[0] = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT; // HDR
    pp.color_target_count = 1;
    dl.pipeline_params = pp;
    if (core.*.get_or_create_pipeline.?(core, &dl.pipeline_params) == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "deferred lighting: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    dl.frame_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = @sizeOf(DeferredFrame),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (dl.frame_uniform == c.KE_GPU_INVALID_HANDLE) return false;
    rebuildFrameBindGroup(dl);

    // Declare the HDR target (also declared by tonemap's reads; declare is
    // idempotent-by-name via the ECS cid registration). The gbuffer targets +
    // depth are declared by the gbuffer plugin (runs first).
    const hdr_cid = core.*.declare.?(core, &c.ke_render_resource_desc{
        .name = "hdr",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0, .height = 0, .scale_x = 1.0, .scale_y = 1.0,
    }, null);

    // Shadow's presence is read from the named-resource table, not a pointer
    // to the shadow plugin: shadow only registers "shadow_map"'s cid when
    // enabled (see ke_render_shadow_create), so an invalid cid here IS the
    // "off" signal — no separate `enabled` flag needs to cross the plugin
    // boundary.
    const shadow_map_cid = core.*.cid.?(core, "shadow_map");
    const shadow_enabled = shadow_map_cid != c.KE_COMPONENT_INVALID;
    // "light_clusters" (not "cluster_lights") is the scheduling ordering tag —
    // cull WRITEs it, this pass READs it; the actual light data crosses
    // through the "cluster_lights" bind group looked up separately below.
    const cluster_lights_cid = core.*.cid.?(core, "light_clusters");

    dl.writes = .{"hdr"};
    dl.reads = .{ "gbuffer_albedo", "gbuffer_normal", "gbuffer_emissive", "depth", "shadow_map", "light_clusters" };
    dl.io = std.mem.zeroes(c.ke_render_pass_io);
    dl.io.writes = @ptrCast(&dl.writes);
    dl.io.writes_count = 1;
    // reads: the gbuffer + depth always exist; shadow_map only when shadow is on.
    dl.io.reads = @ptrCast(&dl.reads);
    dl.io.reads_count = if (shadow_enabled) 6 else 5; // drop shadow_map read when absent (its resource isn't declared)
    dl.io.cmd_slot = 4; // after gbuffer (slot 3), before skybox (5) / tonemap (6)

    var ac: u32 = 0;
    dl.access[ac] = .{ .cid = hdr_cid, .access = c.KE_ACCESS_WRITE };
    ac += 1;
    dl.access[ac] = .{ .cid = core.*.cid.?(core, "gbuffer_albedo"), .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = core.*.cid.?(core, "gbuffer_normal"), .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = core.*.cid.?(core, "gbuffer_emissive"), .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = core.*.cid.?(core, "depth"), .access = c.KE_ACCESS_READ };
    ac += 1;
    if (shadow_enabled) {
        dl.access[ac] = .{ .cid = shadow_map_cid, .access = c.KE_ACCESS_READ };
        ac += 1;
    }
    dl.access[ac] = .{ .cid = cluster_lights_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = camera_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = transform_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = light_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = ambient_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = skybox_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = frame_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access_count = ac;

    // Data the body reads through resolved views. Index order is the
    // query_index passed to ke_system_ctx_view.
    const rd = c.KE_ACCESS_READ;
    dl.queries = std.mem.zeroes([4]c.ke_query_decl);
    dl.queries[0].terms[0] = .{ .cid = camera_cid, .access = rd };
    dl.queries[0].terms[1] = .{ .cid = transform_cid, .access = rd };
    dl.queries[0].term_count = 2;
    dl.queries[1].terms[0] = .{ .cid = skybox_cid, .access = rd };
    dl.queries[1].term_count = 1;
    dl.queries[2].terms[0] = .{ .cid = light_cid, .access = rd };
    dl.queries[2].term_count = 1;
    dl.queries[3].terms[0] = .{ .cid = ambient_cid, .access = rd };
    dl.queries[3].term_count = 1;
    return true;
}

fn destroyHandle(self: ?*c.ke_render_deferred_lighting) callconv(.c) void {
    const dl: *DeferredLightingModule = @ptrCast(@alignCast(self orelse return));
    const dev = dl.device;
    if (dl.gbuf_bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, dl.gbuf_bind_group);
    gpa.destroy(dl);
}

export fn ke_render_deferred_lighting_create(runtime: ?*c.ke_runtime, core: ?*c.ke_render_core,
                                              device: ?*c.ke_gpu_device, ndc: c.ke_ndc_convention,
                                              logger: ?*c.ke_logger, ibl_enabled: c.ke_bool,
                                              camera_cid: c.ke_component_id, transform_cid: c.ke_component_id,
                                              light_cid: c.ke_component_id, ambient_cid: c.ke_component_id,
                                              skybox_cid: c.ke_component_id, frame_cid: c.ke_component_id,
                                              out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_deferred_lighting_handle {
    const empty = c.ke_render_deferred_lighting_handle{ .ref = null, .destroy = null };
    const rt = runtime orelse return empty;
    const core_ref = core orelse return empty;
    const dev = device orelse return empty;

    const dl = gpa.create(DeferredLightingModule) catch return empty;
    dl.* = .{};
    if (!setup(dl, dev, core_ref, ndc, logger, ibl_enabled != 0,
               camera_cid, transform_cid, light_cid, ambient_cid, skybox_cid, frame_cid, out_error))
    {
        gpa.destroy(dl);
        return empty;
    }

    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = "render.deferred_lighting";
    params.phase = c.KE_PHASE_RENDER;
    params.queries = &dl.queries;
    params.query_count = dl.queries.len;
    params.access_list = &dl.access;
    params.access_count = dl.access_count;
    params.pinned_thread = 0;
    params.user_data = dl;
    params.execute = system;
    _ = rt.register_system.?(rt, &params, null);

    return .{ .ref = @ptrCast(dl), .destroy = destroyHandle };
}
