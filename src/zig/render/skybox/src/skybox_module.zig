//! The skybox pass: the render-phase system "render.skybox" that draws the environment cubemap of
//! the skybox component over the frame's color, where the frame's depth is at the far plane. It also owns the
//! creation and teardown of that pass, behind the one factory it exports.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_skybox").logFn };

const zm = @import("zmath");
const c = @import("c");
const R = @import("result").Result(c, .{});
const log = std.log.scoped(.render_skybox);

const heap = @import("heap");
const gpa = heap.gpa;

/// The uniform that `system` uploads whole into `frame_uniform` every frame.
const SkyFrame = extern struct { inv_sky_view_proj: [16]f32 };

/// The state of one skybox pass. `ke_render_skybox_create` allocates it, and `destroyHandle` frees
/// it, or `ke_render_skybox_create` does when creation fails. The runtime keeps its address as the
/// user data of the system, so it must not be moved. The query terms point into its own arrays, and
/// `io` carries the link the pass holds in the chain. After `setup`, only `set` changes.
const depth_hint = [_]c.ke_render_binding_hint{.{ .name = "g_depth", .flags = c.KE_RENDER_BINDING_HINT_DEPTH }};

const shader_layout = c.ke_render_shader_layout_params{
    .shader = "skybox",
    .stages = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT,
    .hints = &depth_hint,
    .hint_count = depth_hint.len,
};

const SkyboxModule = struct {
    core: *c.ke_render_service = undefined,
    device: *c.ke_gpu_device = undefined,
    camera: *c.ke_render_camera = undefined,

    camera_cid: c.ke_component_id = undefined,
    world_transform_cid: c.ke_component_id = undefined,
    skybox_cid: c.ke_component_id = undefined,

    pipeline_params: c.ke_gpu_render_pipeline_params = undefined,
    binder: *c.ke_render_resource_binder = undefined,
    layout: c.ke_render_shader_layout = c.KE_RENDER_BINDING_INVALID,
    set: c.ke_render_resource_set = c.KE_RENDER_BINDING_INVALID,
    frame_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,

    io: c.ke_render_pass_io = std.mem.zeroes(c.ke_render_pass_io),
    access: [6]c.ke_component_access = undefined,
    queries_terms: [3]c.ke_component_access = undefined,
    queries: [2]c.ke_query_decl = undefined,
};

inline fn moduleOf(user: ?*anyopaque) *SkyboxModule {
    return @alignCast(@ptrCast(user.?));
}

/// The body of the "render.skybox" system, which the runtime calls as its `execute` in the render
/// phase. Succeeds with no pass when the first query has no camera, or when the render service
/// gives no pass. A set that cannot be created ends the pass, fails with the binder's code and
/// leaves `set` invalid until the next call. Each frame it draws one full-screen triangle over the frame's color, after rewriting the uniform with the inverse of the camera rotation and projection
/// product. It recreates the set every call, because the environment texture and the
/// depth view can change between frames, and a frame whose skybox query has no row passes the
/// "none" texture handle as the environment.
fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) c.ke_result {
    const sm = moduleOf(user);
    const core = sm.core;

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, 0, &cam_segc);
    if (cam_segc == 0 or cam_segs[0].count == 0) return R.ok;

    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_segs[0].columns[0]));
    const cam_wt: *const c.ke_world_transform_component = @ptrCast(@alignCast(cam_segs[0].columns[1]));

    const pc = core.*.begin_pass.?(core, &sm.io);
    if (pc == null) return R.ok;

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
    const depth_view = pc.*.read.?(pc, c.KE_RENDER_FRAME_DEPTH);

    const bindings = [3]c.ke_render_shader_binding{
        .{ .name = "sky", .buffer = sm.frame_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(SkyFrame), .texture_view = 0, .sampler = 0 },
        .{ .name = "env", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = env_view, .sampler = 0 },
        .{ .name = "g_depth", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = depth_view, .sampler = 0 },
    };
    sm.binder.destroy_set.?(sm.binder, sm.set);
    const made = sm.binder.create_set.?(sm.binder, sm.layout, null, "skybox.set", &bindings, bindings.len, &sm.set);
    if (made != R.ok) {
        core.*.end_pass.?(core, pc);
        log.warn("skybox pass: set creation failed", .{});
        return made;
    }

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &sm.pipeline_params));
    sm.binder.bind_render_set.?(sm.binder, rp, sm.set, null, 0);
    rp.*.draw.?(rp, 3, 1, 0, 0);
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
    return R.ok;
}

/// Called once by `ke_render_skybox_create`, before the system is registered. It joins the chain
/// at the sky stage, creates the layout, pipeline and uniform buffer and fills the access list and
/// the queries. On failure it has stopped at a failing step, and the objects made before that step stay in the module for
/// `destroyModule` to release.
/// Joining, it tells the runtime that the chain, not the runtime, orders the writers of the
/// frame's color.
fn setup(sm: *SkyboxModule, p: *const c.ke_render_skybox_params) R.Error!void {
    const core: *c.ke_render_service = p.service;
    const dev: *c.ke_gpu_device = p.device;
    sm.core = core;
    sm.device = dev;
    sm.camera = p.camera;
    sm.camera_cid = p.camera_cid;
    sm.world_transform_cid = p.world_transform_cid;
    sm.skybox_cid = p.skybox_cid;
    const camera_cid = p.camera_cid;
    const world_transform_cid = p.world_transform_cid;
    const skybox_cid = p.skybox_cid;
    const frame_cid = p.frame_cid;

    sm.io.name = "render.skybox";
    try R.check(core.*.join_chain.?(core, c.KE_RENDER_STAGE_SKY, c.KE_RENDER_CHAIN_DRAW_OVER, &sm.io.chain));
    try R.check(p.runtime.*.declare_self_ordered.?(p.runtime, core.*.cid.?(core, c.KE_RENDER_FRAME_COLOR)));

    sm.binder = core.*.resource_binder.?(core);
    try R.check(sm.binder.create_shader_layout.?(sm.binder, &shader_layout, &sm.layout));

    var sky_vs: c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "skybox", c.KE_GPU_SHADER_STAGE_VERTEX, &sky_vs));
    var sky_fs: c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "skybox", c.KE_GPU_SHADER_STAGE_FRAGMENT, &sky_fs));

    var skp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    skp.label = "skybox.pipeline";
    skp.vertex_module = sky_vs;
    skp.fragment_module = sky_fs;
    skp.vertex_entry = "vs_main";
    skp.fragment_entry = "fs_main";
    skp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    skp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    skp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    skp.blend_state.write_mask = 0x0F;
    skp.depth_stencil.depth_test_enabled = false;
    skp.depth_stencil.depth_write_enabled = false;
    skp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
    try R.check(sm.binder.pipeline_layouts.?(sm.binder, sm.layout, &skp.bind_group_layouts, skp.bind_group_layouts.len, &skp.bind_group_layout_count));
    skp.color_target_formats[0] = core.*.chain_format.?(core, c.KE_RENDER_STAGE_SKY);
    skp.color_target_count = 1;
    sm.pipeline_params = skp;
    if (core.*.get_or_create_pipeline.?(core, &sm.pipeline_params) == c.KE_GPU_INVALID_HANDLE) {
        log.warn("skybox: render pipeline creation failed", .{});
        return error.NotInitialized;
    }

    try R.check(dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .label = "skybox.frame_uniform",
        .initial_data = null,
        .size = @sizeOf(SkyFrame),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, &sm.frame_uniform));

    sm.access = .{
        .{ .cid = core.*.cid.?(core, c.KE_RENDER_FRAME_COLOR), .access = c.KE_ACCESS_WRITE },
        .{ .cid = core.*.cid.?(core, c.KE_RENDER_FRAME_DEPTH), .access = c.KE_ACCESS_READ },
        .{ .cid = camera_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = world_transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = skybox_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = frame_cid, .access = c.KE_ACCESS_READ },
    };

    const rd = c.KE_ACCESS_READ;
    sm.queries_terms = .{ .{ .cid = camera_cid, .access = rd }, .{ .cid = world_transform_cid, .access = rd }, .{ .cid = skybox_cid, .access = rd } };
    sm.queries = .{ .{ .terms = &sm.queries_terms[0], .term_count = 2 }, .{ .terms = &sm.queries_terms[2], .term_count = 1 } };
}

/// Gives the link back and releases each handle that is valid, so it also releases a module that
/// `setup` left half built.
fn destroyModule(sm: *const SkyboxModule) void {
    if (sm.io.chain != c.KE_RENDER_CHAIN_NONE) sm.core.*.leave_chain.?(sm.core, sm.io.chain);
    const dev = sm.device;
    if (sm.frame_uniform != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_buffer.?(dev, sm.frame_uniform);
    if (sm.layout == c.KE_RENDER_BINDING_INVALID) return;
    sm.binder.destroy_set.?(sm.binder, sm.set);
    sm.binder.destroy_shader_layout.?(sm.binder, sm.layout);
}

/// The `destroy` slot of the handle `ke_render_skybox_create` returns. Releases the GPU objects,
/// then frees the module. A null argument is ignored.
fn destroyHandle(self: ?*c.ke_render_skybox) callconv(.c) void {
    const sm: *SkyboxModule = @ptrCast(@alignCast(self orelse return));
    destroyModule(sm);
    gpa.destroy(sm);
}

/// Creates the skybox pass as a render phase system of the params' runtime. A missing runtime,
/// service, device or camera fails as an invalid argument, and a module that
/// cannot be allocated as out of memory. When `setup` or the registration fails, it fails with
/// that step's code and leaves the handle zeroed.
export fn ke_render_skybox_create(params_in: ?*const c.ke_render_skybox_params, out_skybox: [*c]c.ke_render_skybox_handle) callconv(.c) c.ke_result {
    const out = out_skybox orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const p = params_in orelse return R.code(error.InvalidArgument);
    const rt: *c.ke_runtime = p.runtime orelse return R.code(error.InvalidArgument);
    if (p.service == null or p.device == null or p.camera == null)
        return R.code(error.InvalidArgument);

    const sm = gpa.create(SkyboxModule) catch |err| return R.code(err);
    sm.* = .{};
    setup(sm, p) catch |err| {
        destroyModule(sm);
        gpa.destroy(sm);
        return R.code(err);
    };

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
    var system_id: c.ke_system_id = 0;
    const registered = rt.register_system.?(rt, &params, &system_id);
    if (registered != R.ok) {
        destroyModule(sm);
        gpa.destroy(sm);
        return registered;
    }

    out.* = .{ .ref = @ptrCast(sm), .destroy = destroyHandle };
    return R.ok;
}



const testing = std.testing;

const Stubs = @import("stubs").Stubs(c);

test "creating and destroying the skybox pass leaves no block allocated and no GPU resource live" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var camera = std.mem.zeroes(c.ke_render_camera);
    var h: c.ke_render_skybox_handle = undefined;
    try R.check(ke_render_skybox_create(&.{ .runtime = rt.api(), .service = core.api(), .device = dev.api(), .camera = &camera, .camera_cid = 1, .world_transform_cid = 2, .skybox_cid = 3, .frame_cid = 4 }, &h));
    h.destroy.?(h.ref);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a skybox pass whose shader fails to load releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    core.shader_loads_fail = true;
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var camera = std.mem.zeroes(c.ke_render_camera);
    var h: c.ke_render_skybox_handle = undefined;
    try testing.expect(ke_render_skybox_create(&.{ .runtime = rt.api(), .service = core.api(), .device = dev.api(), .camera = &camera, .camera_cid = 1, .world_transform_cid = 2, .skybox_cid = 3, .frame_cid = 4 }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a skybox pass the runtime refuses to register releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    rt.limit = 0;
    var camera = std.mem.zeroes(c.ke_render_camera);
    var h: c.ke_render_skybox_handle = undefined;
    try testing.expect(ke_render_skybox_create(&.{ .runtime = rt.api(), .service = core.api(), .device = dev.api(), .camera = &camera, .camera_cid = 1, .world_transform_cid = 2, .skybox_cid = 3, .frame_cid = 4 }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}
