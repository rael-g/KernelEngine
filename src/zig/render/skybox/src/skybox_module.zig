//! The skybox pass: the system "render.skybox" that declares, at the sky stage, the pass drawing the
//! environment cubemap of the skybox component over the frame's color where the frame's depth is at
//! the far plane. It also owns the creation and teardown of that pass, behind the one factory it
//! exports.

const abi_render_components = @import("abi_render_components");
const abi_render_gpu = @import("abi_render_gpu");
const abi_render_handles = @import("abi_render_handles");
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_skybox").logFn };

const zm = @import("zmath");
const abi_ecs = @import("abi_ecs");
const abi_math = @import("abi_math");
const abi_render = @import("abi_render");
const abi_render_skybox_factory = @import("abi_render_skybox_factory");
const abi_result = @import("abi_result");
const abi_schedule = @import("abi_schedule");
const abi_part = @import("abi_part");
const part = @import("part");
const abi_render_frame = @import("abi_render_frame");
const abi_render_graph = @import("abi_render_graph");
const hooked_systems = @import("hooked_systems");
const abi_spatial = @import("abi_spatial");
const R = @import("result").Result(.{});
const log = std.log.scoped(.render_skybox);

const heap = @import("heap");
const gpa = heap.gpa;
const rg = abi_render_graph.c;

/// The uniform that `queueSystem` uploads whole into `frame_uniform` every frame.
const SkyFrame = extern struct { inv_sky_view_proj: [16]f32 };

const depth_hint = [_]abi_render_gpu.c.ke_render_binding_hint{.{ .name = "g_depth", .flags = abi_render_gpu.c.KE_RENDER_BINDING_HINT_DEPTH }};

const shader_layout = abi_render_gpu.c.ke_render_shader_layout_desc{
    .shader = "skybox",
    .stages = abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX | abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT,
    .hints = &depth_hint,
    .hint_count = depth_hint.len,
};

/// The state of one skybox pass. `ke_render_skybox_create` allocates it, and `destroyOwner` frees
/// it after detaching `systems`, or `ke_render_skybox_create` does when creation fails. The schedule
/// keeps its address as the user data of the system, so it must not be moved. The query terms point
/// into its own arrays. `env_view` and `depth` are what `queueSystem` declared this frame, read by
/// `record`.
const SkyboxModule = struct {
    systems: hooked_systems.Systems(1) = .{},
    frame: *abi_render_frame.c.ke_render_frame = undefined,
    env_view: abi_render.c.ke_gpu_texture_view = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    depth: rg.ke_render_graph_resource = rg.KE_RENDER_GRAPH_RESOURCE_INVALID,
    core: *abi_render.c.ke_render_service = undefined,
    device: *abi_render_gpu.c.ke_gpu_device = undefined,
    camera: *abi_render.c.ke_render_camera = undefined,

    camera_cid: abi_ecs.c.ke_component_id = undefined,
    world_transform_cid: abi_ecs.c.ke_component_id = undefined,
    skybox_cid: abi_ecs.c.ke_component_id = undefined,

    pipeline_params: abi_render_gpu.c.ke_gpu_render_pipeline_desc = undefined,
    binder: *abi_render_gpu.c.ke_render_resource_binder = undefined,
    layout: abi_render.c.ke_render_shader_layout = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    set: abi_render.c.ke_render_resource_set = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    frame_uniform: abi_render.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,

    access: [1]abi_ecs.c.ke_ecs_query_term = undefined,
    queries_terms: [3]abi_ecs.c.ke_ecs_query_term = undefined,
    queries: [2]abi_ecs.c.ke_ecs_query_desc = undefined,
};

inline fn moduleOf(user: ?*anyopaque) *SkyboxModule {
    return @alignCast(@ptrCast(user.?));
}

/// Records the pass: one full-screen triangle over the frame's color. It recreates the set every
/// frame, because the environment texture and the depth's view can change between frames; a set
/// that cannot be created fails with the binder's code and leaves `set` invalid until the next frame.
fn record(user: ?*anyopaque, ctx: ?*rg.ke_render_graph_ctx) callconv(.c) abi_result.c.ke_result {
    const sm = moduleOf(user);
    const core = sm.core;
    const bindings = [3]abi_render_gpu.c.ke_render_shader_binding{
        .{ .name = "sky", .buffer = sm.frame_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(SkyFrame), .texture_view = 0, .sampler = 0 },
        .{ .name = "env", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = sm.env_view, .sampler = 0 },
        .{ .name = "g_depth", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = ctx.?.texture_view.?(ctx, sm.depth), .sampler = 0 },
    };
    sm.binder.destroy_set.?(sm.binder, sm.set);
    const made = sm.binder.create_set.?(sm.binder, sm.layout, null, "skybox.set", &bindings, bindings.len, &sm.set);
    if (made != R.ok) {
        log.warn("skybox pass: set creation failed", .{});
        return made;
    }
    const rp: [*c]abi_render_gpu.c.ke_gpu_render_pass = @ptrCast(ctx.?.render_pass.?(ctx));
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &sm.pipeline_params));
    sm.binder.bind_render_set.?(sm.binder, rp, sm.set, null, 0);
    rp.*.draw.?(rp, 3, 1, 0, 0);
    return R.ok;
}

/// "render.skybox", in the render queue set. Declares nothing when no frame is being declared, the
/// first query has no camera or the second no skybox, so the frame keeps its clear color. Otherwise
/// it rewrites the uniform with the inverse of the camera rotation and projection product, and
/// declares at KE_RENDER_STAGE_SKY the pass drawing over the frame's color and sampling its depth;
/// the graph refusing it fails with its code.
fn queueSystem(ctx: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const sm = moduleOf(user);
    const core = sm.core;
    const frame = sm.frame;
    if (!frame.live.?(frame)) return R.ok;

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, 0, &cam_segc);
    if (cam_segc == 0 or cam_segs.?[0].count == 0) return R.ok;

    var sky_segc: usize = 0;
    const sky_segs = ctx.?.view.?(ctx, 1, &sky_segc);
    if (sky_segc == 0 or sky_segs.?[0].count == 0) return R.ok;
    const env = (@as(*const abi_render_components.c.ke_skybox_component, @ptrCast(@alignCast(sky_segs.?[0].columns.?[0])))).cubemap;

    const cam: *const abi_render_components.c.ke_camera_component = @ptrCast(@alignCast(cam_segs.?[0].columns.?[0]));
    const cam_wt: *const abi_spatial.c.ke_world_transform_component = @ptrCast(@alignCast(cam_segs.?[0].columns.?[1]));

    var bw: u32 = 0;
    var bh: u32 = 0;
    core.*.backbuffer_size.?(core, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    var view_m: abi_math.c.ke_mat4 = undefined;
    sm.camera.view_rotation.?(sm.camera, &cam_wt.matrix, &view_m);
    var proj_m: abi_math.c.ke_mat4 = undefined;
    sm.camera.perspective_projection.?(sm.camera, cam, aspect, &proj_m);
    const sky_vp = zm.mul(zm.loadMat(&view_m.m), zm.loadMat(&proj_m.m));
    var uniform: SkyFrame = .{ .inv_sky_view_proj = undefined };
    zm.storeMat(uniform.inv_sky_view_proj[0..], zm.inverse(sky_vp));
    core.*.upload.?(core, sm.frame_uniform, 0, &uniform, @sizeOf(SkyFrame));
    sm.env_view = core.*.texture_view.?(core, env);
    sm.depth = frame.depth.?(frame);

    var uses = std.mem.zeroes([2]rg.ke_render_graph_use);
    uses[0].resource = frame.color.?(frame);
    uses[0].usage = rg.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT;
    uses[1].resource = sm.depth;
    uses[1].usage = rg.KE_RENDER_GRAPH_USAGE_SAMPLED;
    var desc = std.mem.zeroes(rg.ke_render_graph_pass_desc);
    desc.name = "render.skybox";
    desc.type = rg.KE_RENDER_GRAPH_PASS_RASTER;
    desc.injection_point = abi_render.c.KE_RENDER_STAGE_SKY;
    desc.uses = &uses;
    desc.use_count = uses.len;
    desc.record = record;
    desc.user = sm;
    const graph = frame.graph.?(frame).?;
    var pass: rg.ke_render_graph_pass = 0;
    return graph.add_pass.?(graph, &desc, &pass);
}

/// Called once by `ke_render_skybox_create`. It creates the layout, pipeline and uniform buffer and
/// fills the access list and the queries over the render world. On failure it has stopped at a
/// failing step, and the objects made before that step stay in the module for `destroyModule` to
/// release.
fn setup(sm: *SkyboxModule, service: *abi_render.c.ke_render_service, device: *abi_render_gpu.c.ke_gpu_device, frame: *abi_render_frame.c.ke_render_frame, scene: *abi_render.c.ke_render_scene_resolve, camera: *abi_render.c.ke_render_camera) R.Error!void {
    const core: *abi_render.c.ke_render_service = service;
    const dev: *abi_render_gpu.c.ke_gpu_device = device;
    sm.core = core;
    sm.device = dev;
    sm.camera = camera;
    sm.frame = frame;
    const ids = scene.render_component_ids.?(scene).?;
    sm.camera_cid = ids.*.camera;
    sm.world_transform_cid = ids.*.world_transform;
    sm.skybox_cid = ids.*.skybox;
    const camera_cid = ids.*.camera;
    const world_transform_cid = ids.*.world_transform;
    const skybox_cid = ids.*.skybox;
    const frame_cid = sm.frame.frame_cid.?(sm.frame);

    sm.binder = core.*.resource_binder.?(core).?;
    try R.check(sm.binder.create_shader_layout.?(sm.binder, &shader_layout, &sm.layout));

    var sky_vs: abi_render.c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "skybox", abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX, &sky_vs));
    var sky_fs: abi_render.c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "skybox", abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT, &sky_fs));

    var skp = std.mem.zeroes(abi_render_gpu.c.ke_gpu_render_pipeline_desc);
    skp.label = "skybox.pipeline";
    skp.vertex_module = sky_vs;
    skp.fragment_module = sky_fs;
    skp.vertex_entry = "vs_main";
    skp.fragment_entry = "fs_main";
    skp.primitive_topology = abi_render_gpu.c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    skp.cull_mode = abi_render_gpu.c.KE_GPU_CULL_MODE_NONE;
    skp.front_face = abi_render_gpu.c.KE_GPU_FRONT_FACE_CCW;
    skp.blend_state.write_mask = 0x0F;
    skp.depth_stencil.depth_test_enabled = false;
    skp.depth_stencil.depth_write_enabled = false;
    skp.depth_stencil.depth_compare = abi_render_gpu.c.KE_GPU_COMPARE_ALWAYS;
    try R.check(sm.binder.pipeline_layouts.?(sm.binder, sm.layout, &skp.bind_group_layouts, skp.bind_group_layouts.len, &skp.bind_group_layout_count));
    skp.color_target_formats[0] = sm.frame.color_format.?(sm.frame);
    skp.color_target_count = 1;
    sm.pipeline_params = skp;
    if (core.*.get_or_create_pipeline.?(core, &sm.pipeline_params) == abi_render_gpu.c.KE_GPU_INVALID_HANDLE) {
        log.warn("skybox: render pipeline creation failed", .{});
        return error.NotInitialized;
    }

    try R.check(dev.create_buffer.?(dev, &abi_render_gpu.c.ke_gpu_buffer_desc{
        .label = "skybox.frame_uniform",
        .initial_data = null,
        .size = @sizeOf(SkyFrame),
        .usage = abi_render_gpu.c.KE_GPU_BUFFER_USAGE_UNIFORM | abi_render_gpu.c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, &sm.frame_uniform));

    sm.access = .{.{ .component = frame_cid, .access = abi_ecs.c.KE_ECS_ACCESS_WRITE }};

    const rd = abi_ecs.c.KE_ECS_ACCESS_READ;
    sm.queries_terms = .{ .{ .component = camera_cid, .access = rd }, .{ .component = world_transform_cid, .access = rd }, .{ .component = skybox_cid, .access = rd } };
    sm.queries = .{ .{ .terms = sm.queries_terms[0..].ptr, .term_count = 2 }, .{ .terms = sm.queries_terms[2..].ptr, .term_count = 1 } };
}

/// Releases each handle that is valid, so it also releases a module that `setup` left half built.
fn destroyModule(sm: *const SkyboxModule) void {
    const dev = sm.device;
    if (sm.frame_uniform != abi_render_gpu.c.KE_GPU_INVALID_HANDLE)
        dev.destroy_buffer.?(dev, sm.frame_uniform);
    if (sm.layout == abi_render_gpu.c.KE_RENDER_BINDING_INVALID) return;
    sm.binder.destroy_set.?(sm.binder, sm.set);
    sm.binder.destroy_shader_layout.?(sm.binder, sm.layout);
}

/// The `destroy` of the owner `ke_render_skybox_create` hands out: unregisters the systems, releases the GPU
/// objects and frees the pass; a null argument is ignored.
fn destroyOwner(ref: ?*anyopaque) callconv(.c) void {
    const sm: *SkyboxModule = @ptrCast(@alignCast(ref orelse return));
    sm.systems.unregister();
    destroyModule(sm);
    gpa.destroy(sm);
}

/// The factory declared in skybox_create.h. A missing scene, frame, service, device or camera fails
/// as an invalid argument, and a module that cannot be allocated as out of memory. When `setup`
/// fails, it fails with that step's code and leaves the handle zeroed.
export fn ke_render_skybox_create(
    service_in: ?*abi_render.c.ke_render_service,
    device_in: ?*abi_render_gpu.c.ke_gpu_device,
    frame_in: ?*abi_render_frame.c.ke_render_frame,
    scene_in: ?*abi_render.c.ke_render_scene_resolve,
    camera_in: ?*abi_render.c.ke_render_camera,
    render_queue: ?*abi_schedule.c.ke_schedule,
    render_queue_set: abi_schedule.c.ke_schedule_set_id,
    out_pass: ?*abi_part.c.ke_owner,
) callconv(.c) abi_result.c.ke_result {
    const out = out_pass orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const service = service_in orelse return R.code(error.InvalidArgument);
    const device = device_in orelse return R.code(error.InvalidArgument);
    const frame = frame_in orelse return R.code(error.InvalidArgument);
    const scene = scene_in orelse return R.code(error.InvalidArgument);
    const camera = camera_in orelse return R.code(error.InvalidArgument);
    if (render_queue == null) return R.code(error.InvalidArgument);

    const sm = gpa.create(SkyboxModule) catch |err| return R.code(err);
    sm.* = .{};
    setup(sm, service, device, frame, scene, camera) catch |err| {
        destroyModule(sm);
        gpa.destroy(sm);
        return R.code(err);
    };
    const registered = sm.systems.register(.{.{ .name = "render.skybox", .execute = queueSystem, .user = sm, .hook = 0, .queries = &sm.queries, .access = &sm.access }}, &.{ .{ .schedule = render_queue, .set = render_queue_set } });
    if (registered != R.ok) {
        destroyModule(sm);
        gpa.destroy(sm);
        return registered;
    }
    out.* = .{ .ref = sm, .destroy = destroyOwner };
    return R.ok;
}

pub const parts = [_]abi_part.c.ke_part{
    part.of(ke_render_skybox_create, .{ .name = "render_skybox", .slots = &.{"service", "device", "frame", "scene", "camera"}, .hooks = &.{"render_queue"}, .set_log = @ptrCast(&@import("log").Destination("ke_render_skybox").setLogCallback) }),
};

/// The library's parts.
export fn ke_render_skybox_parts(out_count: ?*usize) callconv(.c) ?*const abi_part.c.ke_part {
    if (out_count) |n| n.* = parts.len;
    return &parts[0];
}

const testing = std.testing;
const zsub = @import("zsub");

const test_ids = std.mem.zeroInit(abi_render.c.ke_render_scene_component_ids, .{ .mesh = 1, .camera = 2, .directional_light = 3, .point_light = 4, .spot_light = 5, .ambient_light = 6, .skybox = 7, .sprite2d = 8, .label = 9, .world_transform = 10 });

fn testComponentIds(_: ?*abi_render.c.ke_render_scene_resolve) callconv(.c) ?*const abi_render.c.ke_render_scene_component_ids {
    return &test_ids;
}

var test_scene: abi_render.c.ke_render_scene_resolve = .{ .handle = null, .component_ids = testComponentIds, .render_component_ids = testComponentIds };

var test_camera_component = std.mem.zeroes(abi_render_components.c.ke_camera_component);
var test_world_transform = std.mem.zeroInit(abi_spatial.c.ke_world_transform_component, .{ .matrix = .{ .m = .{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } } });
var test_sky = std.mem.zeroes(abi_render_components.c.ke_skybox_component);
var camera_columns = [_]?*anyopaque{ @ptrCast(&test_camera_component), @ptrCast(&test_world_transform) };
var sky_columns = [_]?*anyopaque{@ptrCast(&test_sky)};
var camera_segment: abi_ecs.c.ke_ecs_segment = .{ .entities = null, .count = 1, .columns = &camera_columns, .column_count = 2 };
var sky_segment: abi_ecs.c.ke_ecs_segment = .{ .entities = null, .count = 1, .columns = &sky_columns, .column_count = 1 };

fn sceneView(_: ?*abi_schedule.c.ke_schedule_ctx, index: u32, out_count: ?*usize) callconv(.c) ?[*]const abi_ecs.c.ke_ecs_segment {
    out_count.?.* = 1;
    return if (index == 0) (&camera_segment)[0..1] else (&sky_segment)[0..1];
}

var scene_ctx: abi_schedule.c.ke_schedule_ctx = .{ .handle = null, .commands = null, .view = sceneView, .slice = null };

fn identity(args: zsub.For(abi_render.c.ke_render_camera).Args(.view_rotation)) void {
    args[2].?.* = test_world_transform.matrix;
}

fn identityProjection(args: zsub.For(abi_render.c.ke_render_camera).Args(.perspective_projection)) void {
    args[3].?.* = test_world_transform.matrix;
}

/// The parts a pass is made of in a test.
const Rig = struct {
    dev: zsub.For(abi_render_gpu.c.ke_gpu_device),
    binder: zsub.For(abi_render_gpu.c.ke_render_resource_binder),
    core: zsub.For(abi_render.c.ke_render_service),
    schedule: zsub.For(abi_schedule.c.ke_schedule),
    frame: zsub.For(abi_render_frame.c.ke_render_frame),
    graph: zsub.For(rg.ke_render_graph),
    camera: zsub.For(abi_render.c.ke_render_camera),

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
        _ = self.core.when(.texture_view).returnsFresh();
        try self.schedule.init();
        _ = self.schedule.when(.register_system).writesFresh(2);
        try self.graph.init();
        try self.camera.init();
        _ = self.camera.when(.view_rotation).does(identity);
        _ = self.camera.when(.perspective_projection).does(identityProjection);
        try self.frame.init();
        _ = self.frame.when(.frame_cid).returns(11);
        _ = self.frame.when(.live).returns(true);
        _ = self.frame.when(.color).returns(2);
        _ = self.frame.when(.depth).returns(4);
        _ = self.frame.when(.graph).returns(self.graph.api());
        _ = self.frame.when(.color_format).returns(abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT);
    }

    fn deinit(self: *Rig) void {
        self.frame.deinit();
        self.camera.deinit();
        self.graph.deinit();
        self.schedule.deinit();
        self.core.deinit();
        self.binder.deinit();
        self.dev.deinit();
    }

    fn create(self: *Rig, out: *abi_part.c.ke_owner) abi_result.c.ke_result {
        return ke_render_skybox_create(self.core.api(), self.dev.api(), self.frame.api(), &test_scene, self.camera.api(), self.schedule.api(), 4, out);
    }

    fn expectReleased(self: *Rig) !void {
        try self.dev.received(.destroy_buffer).where(zsub.argIsNot(1, abi_render_gpu.c.KE_GPU_INVALID_HANDLE)).sameAs(self.dev.received(.create_buffer));
        try self.binder.received(.destroy_shader_layout).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_shader_layout));
        try self.binder.received(.destroy_set).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_set));
    }
};

fn passOf(h: abi_part.c.ke_owner) *SkyboxModule {
    return @ptrCast(@alignCast(h.ref.?));
}

test "the skybox pass registers its system in its hook, and destroying it unregisters it and releases the GPU objects" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_part.c.ke_owner = undefined;
    try R.check(rig.create(&h));
    try rig.schedule.received(.register_system).times(1);
    h.destroy.?(h.ref);
    try rig.schedule.received(.unregister_system).times(1);
    try rig.expectReleased();
}

test "a camera and a skybox get a sky pass at the sky stage, with its uniform uploaded" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_part.c.ke_owner = undefined;
    try R.check(rig.create(&h));
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, queueSystem(&scene_ctx, passOf(h), 0));
    try rig.graph.received(.add_pass).times(1);
    try rig.core.received(.upload).times(1);
}

test "a frame not being declared gets no sky pass" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.frame.when(.live).returns(false);
    var h: abi_part.c.ke_owner = undefined;
    try R.check(rig.create(&h));
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, queueSystem(&scene_ctx, passOf(h), 0));
    try rig.graph.received(.add_pass).never();
}

test "a skybox pass whose shader fails to load releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.core.when(.load_shader).returns(abi_result.c.KE_RESULT_GENERAL);
    var h: abi_part.c.ke_owner = undefined;
    try testing.expect(rig.create(&h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
}

test "a skybox pass missing its camera is refused as an invalid argument" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_part.c.ke_owner = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_skybox_create(rig.core.api(), rig.dev.api(), rig.frame.api(), &test_scene, null, rig.schedule.api(), 4, &h)));
    try testing.expect(h.ref == null);
}

test "creating and destroying skybox passes leaves no block allocated" {
    try heap.expectNoLeaks();
}

test "the library's parts name render_skybox and their slots" {
    var count: usize = 0;
    const all = ke_render_skybox_parts(&count).?;
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqualStrings("render_skybox", std.mem.span(@as([*]const abi_part.c.ke_part, @ptrCast(all))[0].name.?));
    try std.testing.expectEqual(@as(usize, 6), @as([*]const abi_part.c.ke_part, @ptrCast(all))[0].slot_count);
}
