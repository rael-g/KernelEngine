const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;

const heap = @import("heap");
pub const _DllMainCRTStartup = @import("heap")._DllMainCRTStartup;
const gpa = heap.gpa;

const SkyFrame = extern struct { inv_sky_view_proj: [16]f32 };

const SkyboxModule = struct {
    core: *c.ke_render_service = undefined,
    device: *c.ke_gpu_device = undefined,
    camera: *c.ke_render_camera = undefined,

    camera_cid: c.ke_component_id = undefined,
    world_transform_cid: c.ke_component_id = undefined,
    skybox_cid: c.ke_component_id = undefined,

    pipeline_params: c.ke_gpu_render_pipeline_params = undefined,
    bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE,
    bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    frame_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,

    writes: [1][*c]const u8 = undefined,
    reads: [1][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
    access: [6]c.ke_component_access = undefined,
    queries_terms: [3]c.ke_component_access = undefined,
    queries: [2]c.ke_query_decl = undefined,
};

inline fn moduleOf(user: ?*anyopaque) *SkyboxModule {
    return @alignCast(@ptrCast(user.?));
}

fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const sm = moduleOf(user);
    const core = sm.core;
    const dev = sm.device;

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, 0, &cam_segc);
    if (cam_segc == 0 or cam_segs[0].count == 0) return true;

    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_segs[0].columns[0]));
    const cam_wt: *const c.ke_world_transform_component = @ptrCast(@alignCast(cam_segs[0].columns[1]));

    const pc = core.*.begin_pass.?(core, &sm.io);
    if (pc == null) return true;

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    var view_m: c.ke_mat4 = undefined;
    sm.camera.view_rotation.?(sm.camera, &cam_wt.matrix, &view_m);
    var proj_m: c.ke_mat4 = undefined;
    sm.camera.perspective_projection.?(sm.camera, cam, aspect, &proj_m);
    const sky_vp = zm.mul(zm.loadMat(&view_m.m), zm.loadMat(&proj_m.m));
    var frame: SkyFrame = .{ .inv_sky_view_proj = undefined };
    zm.storeMat(frame.inv_sky_view_proj[0..], zm.inverse(sky_vp));
    core.*.upload.?(core, sm.frame_uniform, 0, &frame, @sizeOf(SkyFrame));

    var sky_segc: usize = 0;
    const sky_segs = ctx.?.view.?(ctx, 1, &sky_segc);
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
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "skybox pass: bind group creation failed", @src().file, @intCast(@src().line), err);
        return false;
    }

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &sm.pipeline_params));
    rp.*.set_bind_group.?(rp, 0, sm.bind_group, null, 0);
    rp.*.draw.?(rp, 3, 1, 0, 0);
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
    return true;
}

fn setup(sm: *SkyboxModule, dev: *c.ke_gpu_device, core: *c.ke_render_service,
         render_camera: *c.ke_render_camera, camera_cid: c.ke_component_id, world_transform_cid: c.ke_component_id,
         skybox_cid: c.ke_component_id, frame_cid: c.ke_component_id, out_error: [*c][*c]c.ke_error) bool {
    sm.core = core;
    sm.device = dev;
    sm.camera = render_camera;
    sm.camera_cid = camera_cid;
    sm.world_transform_cid = world_transform_cid;
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
    skp.depth_stencil.depth_test_enabled = 0;
    skp.depth_stencil.depth_write_enabled = 0;
    skp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
    skp.bind_group_layouts[0] = sm.bgl;
    skp.bind_group_layout_count = 1;
    skp.color_target_formats[0] = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
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
    sm.io.load = 1;
    sm.io.cmd_slot = 5;

    sm.access = .{
        .{ .cid = core.*.cid.?(core, "hdr"), .access = c.KE_ACCESS_WRITE },
        .{ .cid = core.*.cid.?(core, "depth"), .access = c.KE_ACCESS_READ },
        .{ .cid = camera_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = world_transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = skybox_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = frame_cid, .access = c.KE_ACCESS_READ },
    };

    const rd = c.KE_ACCESS_READ;
    sm.queries_terms = .{ .{ .cid = camera_cid, .access = rd }, .{ .cid = world_transform_cid, .access = rd }, .{ .cid = skybox_cid, .access = rd } };
    sm.queries = .{ .{ .terms = &sm.queries_terms[0], .term_count = 2 }, .{ .terms = &sm.queries_terms[2], .term_count = 1 } };
    return true;
}

fn destroyModule(sm: *const SkyboxModule) void {
    const dev = sm.device;
    if (sm.bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, sm.bind_group);
    if (sm.frame_uniform != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_buffer.?(dev, sm.frame_uniform);
    if (sm.bgl != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group_layout.?(dev, sm.bgl);
}

fn destroyHandle(self: ?*c.ke_render_skybox) callconv(.c) void {
    const sm: *SkyboxModule = @ptrCast(@alignCast(self orelse return));
    destroyModule(sm);
    gpa.destroy(sm);
}

export fn ke_render_skybox_create(runtime: ?*c.ke_runtime, core: ?*c.ke_render_service,
                                   device: ?*c.ke_gpu_device, render_camera: ?*c.ke_render_camera,
                                   camera_cid: c.ke_component_id, world_transform_cid: c.ke_component_id,
                                   skybox_cid: c.ke_component_id, frame_cid: c.ke_component_id,
                                   out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_skybox_handle {
    const empty = c.ke_render_skybox_handle{ .ref = null, .destroy = null };
    const rt = runtime orelse return empty;
    const core_ref = core orelse return empty;
    const dev = device orelse return empty;
    const camera_api = render_camera orelse return empty;

    const sm = gpa.create(SkyboxModule) catch return empty;
    sm.* = .{};
    if (!setup(sm, dev, core_ref, camera_api, camera_cid, world_transform_cid, skybox_cid, frame_cid, out_error)) {
        destroyModule(sm);
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
    if (rt.register_system.?(rt, &params, out_error) == 0) {
        destroyModule(sm);
        gpa.destroy(sm);
        return empty;
    }

    return .{ .ref = @ptrCast(sm), .destroy = destroyHandle };
}

const testing = std.testing;

const Stubs = @import("stubs").Stubs(c);

test "creating and destroying the skybox pass leaves no block allocated and no GPU resource live" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init();
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var camera = std.mem.zeroes(c.ke_render_camera);
    const h = ke_render_skybox_create(rt.api(), core.api(), dev.api(), &camera, 1, 2, 3, 4, null);
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a skybox pass whose shader fails to load releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init();
    core.shader_loads_fail = true;
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var camera = std.mem.zeroes(c.ke_render_camera);
    const h = ke_render_skybox_create(rt.api(), core.api(), dev.api(), &camera, 1, 2, 3, 4, null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a skybox pass the runtime refuses to register releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init();
    var rt: Stubs.Runtime = undefined;
    rt.init();
    rt.limit = 0;
    var camera = std.mem.zeroes(c.ke_render_camera);
    const h = ke_render_skybox_create(rt.api(), core.api(), dev.api(), &camera, 1, 2, 3, 4, null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}
