//! The skybox pass: the render-phase system "render.skybox" that draws the environment cubemap of
//! the skybox component over the frame's color, where the frame's depth is at the far plane. It also owns the
//! creation and teardown of that pass, behind the one factory it exports.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_skybox").logFn };

const zm = @import("zmath");
const abi_ecs = @import("abi_ecs");
const abi_math = @import("abi_math");
const abi_render = @import("abi_render");
const abi_render_skybox_factory = @import("abi_render_skybox_factory");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const abi_spatial = @import("abi_spatial");
const R = @import("result").Result(.{});
const log = std.log.scoped(.render_skybox);

const heap = @import("heap");
const gpa = heap.gpa;

/// The uniform that `system` uploads whole into `frame_uniform` every frame.
const SkyFrame = extern struct { inv_sky_view_proj: [16]f32 };

/// The state of one skybox pass. `ke_render_skybox_create` allocates it, and `destroyHandle` frees
/// it, or `ke_render_skybox_create` does when creation fails. The runtime keeps its address as the
/// user data of the system, so it must not be moved. The query terms point into its own arrays, and
/// `io` carries the link the pass holds in the chain. After `setup`, only `set` changes.
const depth_hint = [_]abi_render.ke_render_binding_hint{.{ .name = "g_depth", .flags = abi_render.KE_RENDER_BINDING_HINT_DEPTH }};

const shader_layout = abi_render.ke_render_shader_layout_params{
    .shader = "skybox",
    .stages = abi_render.KE_GPU_SHADER_STAGE_VERTEX | abi_render.KE_GPU_SHADER_STAGE_FRAGMENT,
    .hints = &depth_hint,
    .hint_count = depth_hint.len,
};

/// `destroyHandle` unregisters the system the factory registered before it frees the module.
const SkyboxModule = struct {
    runtime: *abi_runtime.ke_runtime = undefined,
    system: abi_runtime.ke_system_id = 0,
    core: *abi_render.ke_render_service = undefined,
    device: *abi_render.ke_gpu_device = undefined,
    camera: *abi_render.ke_render_camera = undefined,

    camera_cid: abi_ecs.ke_component_id = undefined,
    world_transform_cid: abi_ecs.ke_component_id = undefined,
    skybox_cid: abi_ecs.ke_component_id = undefined,

    pipeline_params: abi_render.ke_gpu_render_pipeline_params = undefined,
    binder: *abi_render.ke_render_resource_binder = undefined,
    layout: abi_render.ke_render_shader_layout = abi_render.KE_RENDER_BINDING_INVALID,
    set: abi_render.ke_render_resource_set = abi_render.KE_RENDER_BINDING_INVALID,
    frame_uniform: abi_render.ke_gpu_buffer = abi_render.KE_GPU_INVALID_HANDLE,

    io: abi_render.ke_render_pass_io = std.mem.zeroes(abi_render.ke_render_pass_io),
    access: [6]abi_runtime.ke_component_access = undefined,
    queries_terms: [3]abi_runtime.ke_component_access = undefined,
    queries: [2]abi_runtime.ke_query_decl = undefined,
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
fn system(ctx: ?*abi_runtime.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const sm = moduleOf(user);
    const core = sm.core;

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, 0, &cam_segc);
    if (cam_segc == 0 or cam_segs.?[0].count == 0) return R.ok;

    const cam: *const abi_render.ke_camera_component = @ptrCast(@alignCast(cam_segs.?[0].columns.?[0]));
    const cam_wt: *const abi_spatial.ke_world_transform_component = @ptrCast(@alignCast(cam_segs.?[0].columns.?[1]));

    const pc = core.*.begin_pass.?(core, &sm.io);
    if (pc == null) return R.ok;

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.?.backbuffer_size.?(pc, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    var view_m: abi_math.ke_mat4 = undefined;
    sm.camera.view_rotation.?(sm.camera, &cam_wt.matrix, &view_m);
    var proj_m: abi_math.ke_mat4 = undefined;
    sm.camera.perspective_projection.?(sm.camera, cam, aspect, &proj_m);
    const sky_vp = zm.mul(zm.loadMat(&view_m.m), zm.loadMat(&proj_m.m));
    var frame: SkyFrame = .{ .inv_sky_view_proj = undefined };
    zm.storeMat(frame.inv_sky_view_proj[0..], zm.inverse(sky_vp));
    core.*.upload.?(core, sm.frame_uniform, 0, &frame, @sizeOf(SkyFrame));

    var sky_segc: usize = 0;
    const sky_segs = ctx.?.view.?(ctx, 1, &sky_segc);
    const env: abi_render.ke_texture_handle = if (sky_segc != 0 and sky_segs.?[0].count != 0)
        (@as(*const abi_render.ke_skybox_component, @ptrCast(@alignCast(sky_segs.?[0].columns.?[0])))).cubemap
    else
        .{ .bits = abi_render.KE_HANDLE_NONE };
    const env_view = core.*.texture_view.?(core, env);
    const depth_view = pc.?.read.?(pc, abi_render.KE_RENDER_FRAME_DEPTH);

    const bindings = [3]abi_render.ke_render_shader_binding{
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

    const rp = pc.?.begin_render.?(pc);
    rp.?.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &sm.pipeline_params));
    sm.binder.bind_render_set.?(sm.binder, rp, sm.set, null, 0);
    rp.?.draw.?(rp, 3, 1, 0, 0);
    rp.?.end.?(rp);
    core.*.end_pass.?(core, pc);
    return R.ok;
}

/// Called once by `ke_render_skybox_create`, before the system is registered. It joins the chain
/// at the sky stage, creates the layout, pipeline and uniform buffer and fills the access list and
/// the queries. On failure it has stopped at a failing step, and the objects made before that step stay in the module for
/// `destroyModule` to release.
/// Joining, it tells the runtime that the chain, not the runtime, orders the writers of the
/// frame's color.
fn setup(sm: *SkyboxModule, p: *const abi_render_skybox_factory.ke_render_skybox_params) R.Error!void {
    const core: *abi_render.ke_render_service = p.service.?;
    const dev: *abi_render.ke_gpu_device = p.device.?;
    sm.core = core;
    sm.device = dev;
    sm.camera = p.camera.?;
    sm.camera_cid = p.camera_cid;
    sm.world_transform_cid = p.world_transform_cid;
    sm.skybox_cid = p.skybox_cid;
    const camera_cid = p.camera_cid;
    const world_transform_cid = p.world_transform_cid;
    const skybox_cid = p.skybox_cid;
    const frame_cid = p.frame_cid;

    sm.io.name = "render.skybox";
    try R.check(core.*.join_chain.?(core, abi_render.KE_RENDER_STAGE_SKY, abi_render.KE_RENDER_CHAIN_DRAW_OVER, &sm.io.chain));
    try R.check(p.runtime.?.declare_self_ordered.?(p.runtime, core.*.cid.?(core, abi_render.KE_RENDER_FRAME_COLOR)));

    sm.binder = core.*.resource_binder.?(core).?;
    try R.check(sm.binder.create_shader_layout.?(sm.binder, &shader_layout, &sm.layout));

    var sky_vs: abi_render.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "skybox", abi_render.KE_GPU_SHADER_STAGE_VERTEX, &sky_vs));
    var sky_fs: abi_render.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "skybox", abi_render.KE_GPU_SHADER_STAGE_FRAGMENT, &sky_fs));

    var skp = std.mem.zeroes(abi_render.ke_gpu_render_pipeline_params);
    skp.label = "skybox.pipeline";
    skp.vertex_module = sky_vs;
    skp.fragment_module = sky_fs;
    skp.vertex_entry = "vs_main";
    skp.fragment_entry = "fs_main";
    skp.primitive_topology = abi_render.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    skp.cull_mode = abi_render.KE_GPU_CULL_MODE_NONE;
    skp.front_face = abi_render.KE_GPU_FRONT_FACE_CCW;
    skp.blend_state.write_mask = 0x0F;
    skp.depth_stencil.depth_test_enabled = false;
    skp.depth_stencil.depth_write_enabled = false;
    skp.depth_stencil.depth_compare = abi_render.KE_GPU_COMPARE_ALWAYS;
    try R.check(sm.binder.pipeline_layouts.?(sm.binder, sm.layout, &skp.bind_group_layouts, skp.bind_group_layouts.len, &skp.bind_group_layout_count));
    skp.color_target_formats[0] = core.*.chain_format.?(core, abi_render.KE_RENDER_STAGE_SKY);
    skp.color_target_count = 1;
    sm.pipeline_params = skp;
    if (core.*.get_or_create_pipeline.?(core, &sm.pipeline_params) == abi_render.KE_GPU_INVALID_HANDLE) {
        log.warn("skybox: render pipeline creation failed", .{});
        return error.NotInitialized;
    }

    try R.check(dev.create_buffer.?(dev, &abi_render.ke_gpu_buffer_params{
        .label = "skybox.frame_uniform",
        .initial_data = null,
        .size = @sizeOf(SkyFrame),
        .usage = abi_render.KE_GPU_BUFFER_USAGE_UNIFORM | abi_render.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, &sm.frame_uniform));

    sm.access = .{
        .{ .cid = core.*.cid.?(core, abi_render.KE_RENDER_FRAME_COLOR), .access = abi_runtime.KE_ACCESS_WRITE },
        .{ .cid = core.*.cid.?(core, abi_render.KE_RENDER_FRAME_DEPTH), .access = abi_runtime.KE_ACCESS_READ },
        .{ .cid = camera_cid, .access = abi_runtime.KE_ACCESS_READ },
        .{ .cid = world_transform_cid, .access = abi_runtime.KE_ACCESS_READ },
        .{ .cid = skybox_cid, .access = abi_runtime.KE_ACCESS_READ },
        .{ .cid = frame_cid, .access = abi_runtime.KE_ACCESS_READ },
    };

    const rd = abi_runtime.KE_ACCESS_READ;
    sm.queries_terms = .{ .{ .cid = camera_cid, .access = rd }, .{ .cid = world_transform_cid, .access = rd }, .{ .cid = skybox_cid, .access = rd } };
    sm.queries = .{ .{ .terms = sm.queries_terms[0..].ptr, .term_count = 2 }, .{ .terms = sm.queries_terms[2..].ptr, .term_count = 1 } };
}

/// Gives the link back and releases each handle that is valid, so it also releases a module that
/// `setup` left half built.
fn destroyModule(sm: *const SkyboxModule) void {
    if (sm.io.chain != abi_render.KE_RENDER_CHAIN_NONE) sm.core.*.leave_chain.?(sm.core, sm.io.chain);
    const dev = sm.device;
    if (sm.frame_uniform != abi_render.KE_GPU_INVALID_HANDLE)
        dev.destroy_buffer.?(dev, sm.frame_uniform);
    if (sm.layout == abi_render.KE_RENDER_BINDING_INVALID) return;
    sm.binder.destroy_set.?(sm.binder, sm.set);
    sm.binder.destroy_shader_layout.?(sm.binder, sm.layout);
}

/// The `destroy` slot of the handle `ke_render_skybox_create` returns. Releases the GPU objects,
/// then frees the module. A null argument is ignored.
fn destroyHandle(self: ?*abi_render_skybox_factory.ke_render_skybox) callconv(.c) void {
    const sm: *SkyboxModule = @ptrCast(@alignCast(self orelse return));
    _ = sm.runtime.unregister_system.?(sm.runtime, sm.system);
    destroyModule(sm);
    gpa.destroy(sm);
}

/// Creates the skybox pass as a render phase system of the params' runtime. A missing runtime,
/// service, device or camera fails as an invalid argument, and a module that
/// cannot be allocated as out of memory. When `setup` or the registration fails, it fails with
/// that step's code and leaves the handle zeroed.
export fn ke_render_skybox_create(params_in: ?*const abi_render_skybox_factory.ke_render_skybox_params, out_skybox: [*c]abi_render_skybox_factory.ke_render_skybox_handle) callconv(.c) abi_result.ke_result {
    const out = out_skybox orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const p = params_in orelse return R.code(error.InvalidArgument);
    const rt: *abi_runtime.ke_runtime = p.runtime orelse return R.code(error.InvalidArgument);
    if (p.service == null or p.device == null or p.camera == null)
        return R.code(error.InvalidArgument);

    const sm = gpa.create(SkyboxModule) catch |err| return R.code(err);
    sm.* = .{};
    setup(sm, p) catch |err| {
        destroyModule(sm);
        gpa.destroy(sm);
        return R.code(err);
    };

    var params = std.mem.zeroes(abi_runtime.ke_runtime_system_params);
    params.name = "render.skybox";
    params.phase = abi_runtime.KE_PHASE_RENDER;
    params.queries = &sm.queries;
    params.query_count = sm.queries.len;
    params.access_list = &sm.access;
    params.access_count = sm.access.len;
    params.user_data = sm;
    params.execute = system;
    var system_id: abi_runtime.ke_system_id = 0;
    const registered = rt.register_system.?(rt, &params, &system_id);
    if (registered != R.ok) {
        destroyModule(sm);
        gpa.destroy(sm);
        return registered;
    }
    sm.runtime = rt;
    sm.system = system_id;

    out.* = .{ .ref = @ptrCast(sm), .destroy = destroyHandle };
    return R.ok;
}



const testing = std.testing;

const zsub = @import("zsub");

const Rig = struct {
    dev: zsub.For(abi_render.ke_gpu_device),
    binder: zsub.For(abi_render.ke_render_resource_binder),
    core: zsub.For(abi_render.ke_render_service),
    rt: zsub.For(abi_runtime.ke_runtime),

    fn init(self: *Rig) !void {
        try self.dev.init();
        _ = self.dev.when(.create_buffer).writesFresh(2);
        try self.binder.init();
        _ = self.binder.when(.create_shader_layout).writesFresh(2);
        _ = self.binder.when(.create_set).writesFresh(6);
        try self.core.init();
        _ = self.core.when(.resource_binder).returns(self.binder.api());
        _ = self.core.when(.load_shader).writesFresh(3);
        _ = self.core.when(.get_or_create_pipeline).returnsFresh();
        _ = self.core.when(.cid).returnsFresh();
        _ = self.core.when(.texture_view).returnsFresh();
        _ = self.core.when(.join_chain).writesFresh(3);
        _ = self.core.when(.chain_format).does(chainFormat);
        try self.rt.init();
        _ = self.rt.when(.register_system).writesFresh(2);
    }

    fn deinit(self: *Rig) void {
        self.rt.deinit();
        self.core.deinit();
        self.binder.deinit();
        self.dev.deinit();
    }

    fn expectReleased(self: *Rig) !void {
        try self.dev.received(.destroy_buffer).where(zsub.argIsNot(1, abi_render.KE_GPU_INVALID_HANDLE)).sameAs(self.dev.received(.create_buffer));
        try self.binder.received(.destroy_shader_layout).where(zsub.argIsNot(1, abi_render.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_shader_layout));
        try self.binder.received(.destroy_set).where(zsub.argIsNot(1, abi_render.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_set));
        try self.core.received(.leave_chain).sameAs(self.core.received(.join_chain));
    }
};

fn chainFormat(args: zsub.For(abi_render.ke_render_service).Args(.chain_format)) abi_render.ke_gpu_texture_format {
    return if (args[1] >= abi_render.KE_RENDER_STAGE_TONEMAP) abi_render.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM else abi_render.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
}

test "creating and destroying the skybox pass leaves no block allocated and no GPU resource live" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var camera = std.mem.zeroes(abi_render.ke_render_camera);
    var h: abi_render_skybox_factory.ke_render_skybox_handle = undefined;
    try R.check(ke_render_skybox_create(&.{ .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .camera = &camera, .camera_cid = 1, .world_transform_cid = 2, .skybox_cid = 3, .frame_cid = 4 }, &h));
    h.destroy.?(h.ref);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}

test "destroying the skybox pass unregisters every system it registered" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var camera = std.mem.zeroes(abi_render.ke_render_camera);
    var h: abi_render_skybox_factory.ke_render_skybox_handle = undefined;
    try R.check(ke_render_skybox_create(&.{ .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .camera = &camera, .camera_cid = 1, .world_transform_cid = 2, .skybox_cid = 3, .frame_cid = 4 }, &h));
    h.destroy.?(h.ref);
    try rig.rt.received(.register_system).atLeast(1);
    try rig.rt.received(.unregister_system).where(zsub.argIs(1, @as(abi_runtime.ke_system_id, 0))).never();
    try rig.rt.received(.unregister_system).sameAs(rig.rt.received(.register_system));
}

test "a skybox pass whose shader fails to load releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.core.when(.load_shader).returns(abi_result.KE_RESULT_GENERAL);
    var camera = std.mem.zeroes(abi_render.ke_render_camera);
    var h: abi_render_skybox_factory.ke_render_skybox_handle = undefined;
    try testing.expect(ke_render_skybox_create(&.{ .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .camera = &camera, .camera_cid = 1, .world_transform_cid = 2, .skybox_cid = 3, .frame_cid = 4 }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}

test "a skybox pass the runtime refuses to register releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.rt.when(.register_system).returns(abi_result.KE_RESULT_OUT_OF_MEMORY);
    var camera = std.mem.zeroes(abi_render.ke_render_camera);
    var h: abi_render_skybox_factory.ke_render_skybox_handle = undefined;
    try testing.expect(ke_render_skybox_create(&.{ .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .camera = &camera, .camera_cid = 1, .world_transform_cid = 2, .skybox_cid = 3, .frame_cid = 4 }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}
