const std = @import("std");
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;

const gpa = std.heap.c_allocator;

// Skybox — a standalone pass. Fullscreen triangle that fills the pixels the
// geometry did not cover (G-buffer depth at far), sampling the environment
// cubemap by the reconstructed view direction. Runs after deferred-lighting
// (which shaded the covered pixels) and before tonemap, writing "hdr" with load
// (composite, not clear). No depth attachment — it discards covered pixels by
// texel-fetching the depth buffer.
//
// A standalone plugin: talks to the rest of the render pipeline only through
// the borrowed ke_render_core/ke_runtime handles passed to create() — it never
// sees another pass's private struct. "depth" is resolved by name (the
// producing pass declares it before this one registers its own system).

// Matches skybox.slang's SkyFrame.
const SkyFrame = extern struct { inv_sky_view_proj: [16]f32 };

const SkyboxModule = struct {
    core: *c.ke_render_core = undefined,
    device: *c.ke_gpu_device = undefined,
    ndc: c.ke_ndc_convention = undefined,

    camera_cid: c.ke_component_id = undefined,
    transform_cid: c.ke_component_id = undefined,
    skybox_cid: c.ke_component_id = undefined,

    // Re-queried via core.get_or_create_pipeline every record() call — see
    // forward_module.zig's ForwardModule.pipeline_params for why a handle
    // cached once at setup can't observe the async real-PSO upgrade.
    pipeline_params: c.ke_gpu_render_pipeline_params = undefined,
    bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE, // set 0
    bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE, // rebuilt per frame (transient depth view)
    frame_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,

    writes: [1][*c]const u8 = undefined,
    reads: [1][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
    access: [6]c.ke_component_access = undefined,
    // Resolved single-threaded by the runtime before the wave dispatches; the
    // body then reads plain memory via ke_system_ctx_view and touches the ECS
    // not at all.
    queries: [2]c.ke_query_decl = undefined, // [camera, transform], [skybox]
};

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

fn makePerspective(ndc: c.ke_ndc_convention, fovy: f32, aspect: f32, near: f32, far: f32) zm.Mat {
    var p = if (ndc.z_zero_to_one != 0)
        zm.perspectiveFovLh(fovy, aspect, near, far)
    else
        zm.perspectiveFovLhGl(fovy, aspect, near, far);
    if (ndc.y_flip != 0) p[1][1] = -p[1][1];
    return p;
}

inline fn moduleOf(user: ?*anyopaque) *SkyboxModule {
    return @alignCast(@ptrCast(user.?));
}

fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const sm = moduleOf(user);
    const core = sm.core;
    const dev = sm.device;

    // View 0 = [camera, transform]; the first match is the active camera.
    var cam_segc: usize = 0;
    const cam_segs = c.ke_system_ctx_view(ctx, 0, &cam_segc);
    if (cam_segc == 0 or cam_segs[0].count == 0) return; // no camera → deferred already cleared hdr

    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_segs[0].columns[0]));
    const cam_tc: *const c.ke_transform_component = @ptrCast(@alignCast(cam_segs[0].columns[1]));

    const pc = core.*.begin_pass.?(core, ctx, &sm.io);
    if (pc == null) return;

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    // Rotation-only view (translation zeroed) × proj, inverted → clip-to-world
    // direction so the cubemap stays centred on the camera (infinite background).
    const view = cameraView(cam_tc);
    var vm: [16]f32 = undefined;
    zm.storeMat(vm[0..], view);
    vm[12] = 0;
    vm[13] = 0;
    vm[14] = 0;
    const fov_rad = cam.fov * @as(f32, std.math.pi / 180.0);
    const proj = makePerspective(sm.ndc, fov_rad, aspect, cam.near_plane, cam.far_plane);
    const sky_vp = zm.mul(zm.loadMat(vm[0..]), proj);
    var frame: SkyFrame = .{ .inv_sky_view_proj = undefined };
    zm.storeMat(frame.inv_sky_view_proj[0..], zm.inverse(sky_vp));
    core.*.upload.?(core, sm.frame_uniform, 0, &frame, @sizeOf(SkyFrame));

    // Environment cubemap from the first skybox entity (default black otherwise).
    // View 1 = [skybox].
    var sky_segc: usize = 0;
    const sky_segs = c.ke_system_ctx_view(ctx, 1, &sky_segc);
    const env: c.ke_texture_handle = if (sky_segc != 0 and sky_segs[0].count != 0)
        (@as(*const c.ke_skybox_component, @ptrCast(@alignCast(sky_segs[0].columns[0])))).cubemap
    else
        .{ .bits = c.KE_HANDLE_NONE };
    const env_view = core.*.texture_view.?(core, env);
    const depth_view = pc.*.read.?(pc, "depth");
    const smp = core.*.sampler.?(core);

    const entries = [4]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = sm.frame_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(SkyFrame), .texture_view = 0, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = env_view, .sampler = 0 },
        .{ .binding = 2, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
        .{ .binding = 3, .type = c.KE_GPU_BINDING_TYPE_DEPTH_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = depth_view, .sampler = 0 },
    };
    if (sm.bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, sm.bind_group);
    var err: ?*c.ke_error = null;
    sm.bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = sm.bgl,
        .entry_count = 4,
        .entries = &entries,
    }, &err);
    if (sm.bind_group == c.KE_GPU_INVALID_HANDLE) {
        core.*.end_pass.?(core, pc);
        return;
    }

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &sm.pipeline_params));
    rp.*.set_bind_group.?(rp, 0, sm.bind_group, null, 0);
    rp.*.draw.?(rp, 3, 1, 0, 0); // fullscreen triangle
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

fn setup(sm: *SkyboxModule, dev: *c.ke_gpu_device, core: *c.ke_render_core,
         ndc: c.ke_ndc_convention, camera_cid: c.ke_component_id, transform_cid: c.ke_component_id,
         skybox_cid: c.ke_component_id, frame_cid: c.ke_component_id, out_error: [*c][*c]c.ke_error) bool {
    sm.core = core;
    sm.device = dev;
    sm.ndc = ndc;
    sm.camera_cid = camera_cid;
    sm.transform_cid = transform_cid;
    sm.skybox_cid = skybox_cid;

    const frag = c.KE_GPU_SHADER_STAGE_FRAGMENT;
    const bgl_entries = [_]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_VERTEX | frag, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 1, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = c.KE_GPU_TEXTURE_DIM_CUBE },
        .{ .binding = 2, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 3, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_DEPTH_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    sm.bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 4,
        .entries = &bgl_entries,
    });

    // Neither the path nor the shader format is named here — core.load_shader
    // resolves both. The core owns the result; this pass never destroys it.
    const sky_vs = core.*.load_shader.?(core, "skybox", c.KE_GPU_SHADER_STAGE_VERTEX, out_error);
    if (sky_vs == c.KE_GPU_INVALID_HANDLE) return false;
    const sky_fs = core.*.load_shader.?(core, "skybox", c.KE_GPU_SHADER_STAGE_FRAGMENT, out_error);
    if (sky_fs == c.KE_GPU_INVALID_HANDLE) return false;

    var skp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    skp.vertex_module = sky_vs;
    skp.fragment_module = sky_fs;
    skp.vertex_entry = "vs_main";
    skp.fragment_entry = "fs_main";
    skp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    skp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    skp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    skp.blend_state.write_mask = 0x0F;
    skp.depth_stencil.depth_test_enabled = 0; // no depth attachment; occlusion via texel-fetch discard
    skp.depth_stencil.depth_write_enabled = 0;
    skp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
    skp.bind_group_layouts[0] = sm.bgl;
    skp.bind_group_layout_count = 1;
    skp.color_target_formats[0] = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT; // HDR intermediate
    skp.color_target_count = 1;
    sm.pipeline_params = skp;
    if (core.*.get_or_create_pipeline.?(core, &sm.pipeline_params) == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "skybox: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    sm.frame_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = @sizeOf(SkyFrame),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (sm.frame_uniform == c.KE_GPU_INVALID_HANDLE) return false;

    sm.writes = .{"hdr"};
    sm.reads = .{"depth"};
    sm.io = std.mem.zeroes(c.ke_render_pass_io);
    sm.io.writes = @ptrCast(&sm.writes);
    sm.io.writes_count = 1;
    sm.io.reads = @ptrCast(&sm.reads);
    sm.io.reads_count = 1;
    sm.io.load = 1; // composite over deferred-lighting's output, don't clear
    sm.io.cmd_slot = 5; // after deferred-lighting (4), before tonemap (6)

    sm.access = .{
        .{ .cid = core.*.cid.?(core, "hdr"), .access = c.KE_ACCESS_WRITE },
        .{ .cid = core.*.cid.?(core, "depth"), .access = c.KE_ACCESS_READ },
        .{ .cid = camera_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = skybox_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = frame_cid, .access = c.KE_ACCESS_READ },
    };

    // Data the body reads through resolved views. Index order is the
    // query_index passed to ke_system_ctx_view.
    const rd = c.KE_ACCESS_READ;
    sm.queries = std.mem.zeroes([2]c.ke_query_decl);
    sm.queries[0].terms[0] = .{ .cid = camera_cid, .access = rd };
    sm.queries[0].terms[1] = .{ .cid = transform_cid, .access = rd };
    sm.queries[0].term_count = 2;
    sm.queries[1].terms[0] = .{ .cid = skybox_cid, .access = rd };
    sm.queries[1].term_count = 1;
    return true;
}

fn destroyModule(sm: *const SkyboxModule) void {
    const dev = sm.device;
    if (sm.bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, sm.bind_group);
}

fn destroyHandle(self: ?*c.ke_render_skybox) callconv(.c) void {
    const sm: *SkyboxModule = @ptrCast(@alignCast(self orelse return));
    destroyModule(sm);
    gpa.destroy(sm);
}

export fn ke_render_skybox_create(runtime: ?*c.ke_runtime, core: ?*c.ke_render_core,
                                   device: ?*c.ke_gpu_device, ndc: c.ke_ndc_convention,
                                   camera_cid: c.ke_component_id, transform_cid: c.ke_component_id,
                                   skybox_cid: c.ke_component_id, frame_cid: c.ke_component_id,
                                   out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_skybox_handle {
    const empty = c.ke_render_skybox_handle{ .ref = null, .destroy = null };
    const rt = runtime orelse return empty;
    const core_ref = core orelse return empty;
    const dev = device orelse return empty;

    const sm = gpa.create(SkyboxModule) catch return empty;
    sm.* = .{};
    if (!setup(sm, dev, core_ref, ndc, camera_cid, transform_cid, skybox_cid, frame_cid, out_error)) {
        gpa.destroy(sm);
        return empty;
    }

    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = "render.skybox";
    params.phase = c.KE_PHASE_RENDER;
    params.queries = &sm.queries;
    params.query_count = sm.queries.len;
    params.access_list = &sm.access;
    params.access_count = sm.access.len;
    params.pinned_thread = 0;
    params.user_data = sm;
    params.execute = system;
    _ = rt.register_system.?(rt, &params, null);

    return .{ .ref = @ptrCast(sm), .destroy = destroyHandle };
}
