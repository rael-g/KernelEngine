//! The deferred lighting pass: the system "render.deferred_lighting" that declares, at the opaque
//! stage, the pass turning the published gbuffer into lit colour with one full-screen draw over the
//! frame's color. It also owns the creation and teardown of that pass, behind the one factory it
//! exports.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_components = @import("abi_render_components");
const abi_render_gpu = @import("abi_render_gpu");
const abi_render_handles = @import("abi_render_handles");
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_deferred_lighting").logFn };

const abi_ecs = @import("abi_ecs");
const abi_part = @import("abi_part");
const abi_render = @import("abi_render");
const abi_render_deferred_lighting_factory = @import("abi_render_deferred_lighting_factory");
const abi_render_frame = @import("abi_render_frame");
const abi_render_graph = @import("abi_render_graph");
const abi_result = @import("abi_result");
const abi_settings = @import("abi_settings");
const settings_schema = @import("settings_schema");
const abi_schedule = @import("abi_schedule");
const hooked_systems = @import("hooked_systems");
const R = @import("result").Result(.{});

const heap = @import("heap");
const gpa = heap.gpa;
const Features = @import("feature_bindings");
const rg = abi_render_graph.c;

const depth_hint = [_]abi_render_gpu.c.ke_render_binding_hint{.{ .name = "g_depth", .flags = abi_render_gpu.c.KE_RENDER_BINDING_HINT_DEPTH }};

const shader_layout = abi_render_gpu.c.ke_render_shader_layout_desc{
    .shader = "deferred_lighting",
    .stages = abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX | abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT,
    .hints = &depth_hint,
    .hint_count = depth_hint.len,
};

/// The state of one pass, created by `ke_render_deferred_lighting_create` and freed by
/// `destroyOwner` after it unregisters `systems`. `gbuffer`, `depth`, `features` and `env_cubemap` are
/// what `queueSystem` found this frame, read by `record`, which replaces both sets each frame since
/// every view it binds is the graph's for that frame.
const DeferredLightingModule = struct {
    systems: hooked_systems.Systems(1) = .{},
    core: *abi_render.c.ke_render_service = undefined,
    device: *abi_render_gpu.c.ke_gpu_device = undefined,
    frame: *abi_render_frame.c.ke_render_frame = undefined,
    ibl_enabled: bool = true,

    gbuffer: [3]rg.ke_render_graph_resource = .{ 0, 0, 0 },
    depth: rg.ke_render_graph_resource = rg.KE_RENDER_GRAPH_RESOURCE_INVALID,
    features: Features.Published = undefined,

    pipeline_params: abi_render_gpu.c.ke_gpu_render_pipeline_desc = undefined,
    binder: *abi_render_gpu.c.ke_render_resource_binder = undefined,
    layout: abi_asset_resolver.c.ke_render_shader_layout = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    frame_set: abi_asset_resolver.c.ke_render_resource_set = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    gbuffer_set: abi_asset_resolver.c.ke_render_resource_set = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    env_cubemap: abi_render_handles.c.ke_texture_handle = .{ .bits = abi_render_handles.c.KE_HANDLE_NONE },

    access: [1]abi_ecs.c.ke_ecs_query_term = undefined,
    queries_terms: [3]abi_ecs.c.ke_ecs_query_term = undefined,
    queries: [2]abi_ecs.c.ke_ecs_query_desc = undefined,
};

const log = std.log.scoped(.render_deferred_lighting);

inline fn moduleOf(user: ?*anyopaque) *DeferredLightingModule {
    return @alignCast(@ptrCast(user.?));
}

const gbuffer_names = [3][*:0]const u8{ abi_render.c.KE_RENDER_RESOURCE_GBUFFER_ALBEDO, abi_render.c.KE_RENDER_RESOURCE_GBUFFER_NORMAL, abi_render.c.KE_RENDER_RESOURCE_GBUFFER_EMISSIVE };
const gbuffer_parameters = [3][*:0]const u8{ "g_albedo", "g_normal", "g_emissive" };

/// Records the pass. The frame set binds the feature bindings over the environment cubemap, or the
/// black cube when `ibl_enabled` is false; the gbuffer set binds the gbuffer and the depth. A set
/// that cannot be created fails with the binder's code.
fn record(user: ?*anyopaque, ctx_in: ?*rg.ke_render_graph_ctx) callconv(.c) abi_result.c.ke_result {
    const dl = moduleOf(user);
    const core = dl.core;
    const ctx = ctx_in.?;
    const env_view = core.*.texture_view.?(core, if (dl.ibl_enabled) dl.env_cubemap else .{ .bits = abi_render_handles.c.KE_HANDLE_NONE });
    var features: [Features.count]abi_render_gpu.c.ke_render_shader_binding = undefined;
    Features.fill(core, ctx, env_view, dl.features, &features);
    dl.binder.destroy_set.?(dl.binder, dl.frame_set);
    const framed = dl.binder.create_set.?(dl.binder, dl.layout, null, "deferred_lighting.frame_set", &features, features.len, &dl.frame_set);
    if (framed != R.ok) {
        log.warn("deferred lighting pass: frame set creation failed", .{});
        return framed;
    }
    var bindings: [4]abi_render_gpu.c.ke_render_shader_binding = undefined;
    for (dl.gbuffer, gbuffer_parameters, 0..) |r, name, i| bindings[i] = .{ .name = name, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = ctx.texture_view.?(ctx, r), .sampler = 0 };
    bindings[3] = .{ .name = "g_depth", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = ctx.texture_view.?(ctx, dl.depth), .sampler = 0 };
    dl.binder.destroy_set.?(dl.binder, dl.gbuffer_set);
    const made = dl.binder.create_set.?(dl.binder, dl.layout, "gbuffer", "deferred_lighting.gbuffer_set", &bindings, bindings.len, &dl.gbuffer_set);
    if (made != R.ok) {
        log.warn("deferred lighting pass: gbuffer set creation failed", .{});
        return made;
    }
    const rp: [*c]abi_render_gpu.c.ke_gpu_render_pass = @ptrCast(ctx.render_pass.?(ctx));
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &dl.pipeline_params));
    dl.binder.bind_render_set.?(dl.binder, rp, dl.frame_set, null, 0);
    dl.binder.bind_render_set.?(dl.binder, rp, dl.gbuffer_set, null, 0);
    rp.*.draw.?(rp, 3, 1, 0, 0);
    return R.ok;
}

/// "render.deferred_lighting", in the render queue set. Declares nothing when no frame is being
/// declared, no camera is in the render world or no gbuffer was published. Otherwise the sky
/// selects the environment, and it declares at KE_RENDER_STAGE_OPAQUE the pass drawing over the
/// frame's color, sampling the gbuffer, the depth and the published features; the graph refusing
/// it fails with its code.
fn queueSystem(ctx: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const dl = moduleOf(user);
    const frame = dl.frame;
    if (!frame.live.?(frame)) return R.ok;

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, 0, &cam_segc);
    if (cam_segc == 0 or cam_segs.?[0].count == 0) return R.ok;
    for (gbuffer_names, 0..) |name, i| {
        dl.gbuffer[i] = frame.find.?(frame, name);
        if (dl.gbuffer[i] == rg.KE_RENDER_GRAPH_RESOURCE_INVALID) return R.ok;
    }

    var sky_segc: usize = 0;
    const sky_segs = ctx.?.view.?(ctx, 1, &sky_segc);
    dl.env_cubemap = if (sky_segc != 0 and sky_segs.?[0].count != 0)
        (@as(*const abi_render_components.c.ke_skybox_component, @ptrCast(@alignCast(sky_segs.?[0].columns.?[0])))).cubemap
    else
        .{ .bits = abi_render_handles.c.KE_HANDLE_NONE };
    dl.depth = frame.depth.?(frame);
    dl.features = Features.find(frame);

    var uses = std.mem.zeroes([5 + Features.count]rg.ke_render_graph_use);
    uses[0].resource = frame.color.?(frame);
    uses[0].usage = rg.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT;
    for (dl.gbuffer, 0..) |r, i| {
        uses[1 + i].resource = r;
        uses[1 + i].usage = rg.KE_RENDER_GRAPH_USAGE_SAMPLED;
    }
    uses[4].resource = dl.depth;
    uses[4].usage = rg.KE_RENDER_GRAPH_USAGE_SAMPLED;
    const feature_count = Features.uses(dl.features, uses[5..]);
    var desc = std.mem.zeroes(rg.ke_render_graph_pass_desc);
    desc.name = "render.deferred_lighting";
    desc.type = rg.KE_RENDER_GRAPH_PASS_RASTER;
    desc.injection_point = abi_render.c.KE_RENDER_STAGE_OPAQUE;
    desc.uses = &uses;
    desc.use_count = 5 + feature_count;
    desc.record = record;
    desc.user = dl;
    const graph = frame.graph.?(frame).?;
    var pass: rg.ke_render_graph_pass = 0;
    return graph.add_pass.?(graph, &desc, &pass);
}

/// Called once by `ke_render_deferred_lighting_create` on a freshly reset block. It succeeds only
/// when every object it creates exists, the pipeline included, and the access list and queries are
/// filled over the render world. On failure, the objects already created stay in the block for the
/// caller to release through `destroyModule`.
/// The pass's settings, with this implementation's defaults.
const Settings = struct {
    ibl_enabled: bool = true,
};

fn setup(dl: *DeferredLightingModule, service: *abi_render.c.ke_render_service, device: *abi_render_gpu.c.ke_gpu_device, frame: *abi_render_frame.c.ke_render_frame, scene: *abi_render.c.ke_render_scene_resolve, config: *const Settings) R.Error!void {
    const core: *abi_render.c.ke_render_service = service;
    const ids = scene.render_component_ids.?(scene).?;
    dl.core = core;
    dl.device = device;
    dl.frame = frame;
    dl.ibl_enabled = config.ibl_enabled;

    dl.binder = core.*.resource_binder.?(core).?;
    try R.check(dl.binder.create_shader_layout.?(dl.binder, &shader_layout, &dl.layout));

    var vs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "deferred_lighting", abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX, &vs));
    var fs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "deferred_lighting", abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT, &fs));

    var pp = std.mem.zeroes(abi_render_gpu.c.ke_gpu_render_pipeline_desc);
    pp.label = "deferred_lighting.pipeline";
    pp.vertex_module = vs;
    pp.fragment_module = fs;
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = abi_render_gpu.c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = abi_render_gpu.c.KE_GPU_CULL_MODE_NONE;
    pp.front_face = abi_render_gpu.c.KE_GPU_FRONT_FACE_CCW;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = false;
    pp.depth_stencil.depth_write_enabled = false;
    pp.depth_stencil.depth_compare = abi_render_gpu.c.KE_GPU_COMPARE_ALWAYS;
    try R.check(dl.binder.pipeline_layouts.?(dl.binder, dl.layout, &pp.bind_group_layouts, pp.bind_group_layouts.len, &pp.bind_group_layout_count));
    pp.color_target_formats[0] = dl.frame.color_format.?(dl.frame);
    pp.color_target_count = 1;
    dl.pipeline_params = pp;
    if (core.*.get_or_create_pipeline.?(core, &dl.pipeline_params) == abi_render_gpu.c.KE_GPU_INVALID_HANDLE) {
        log.warn("deferred lighting: render pipeline creation failed", .{});
        return error.NotInitialized;
    }


    dl.access = .{.{ .component = dl.frame.frame_cid.?(dl.frame), .access = abi_ecs.c.KE_ECS_ACCESS_WRITE }};
    const rd = abi_ecs.c.KE_ECS_ACCESS_READ;
    dl.queries_terms = .{ .{ .component = ids.*.camera, .access = rd }, .{ .component = ids.*.world_transform, .access = rd }, .{ .component = ids.*.skybox, .access = rd } };
    dl.queries = .{ .{ .terms = dl.queries_terms[0..].ptr, .term_count = 2 }, .{ .terms = dl.queries_terms[2..].ptr, .term_count = 1 } };
}

/// Releases the sets and the layout the block holds, those still absent skipped. It leaves the
/// pipeline and the shader modules alone, and does not free the block, so it can release a partly
/// built one.
fn destroyModule(dl: *const DeferredLightingModule) void {
    if (dl.layout == abi_render_gpu.c.KE_RENDER_BINDING_INVALID) return;
    dl.binder.destroy_set.?(dl.binder, dl.gbuffer_set);
    dl.binder.destroy_set.?(dl.binder, dl.frame_set);
    dl.binder.destroy_shader_layout.?(dl.binder, dl.layout);
}

/// The `destroy` of the owner `ke_render_deferred_lighting_create` hands out: unregisters the systems, releases the GPU
/// objects and frees the pass; a null argument is ignored.
fn destroyOwner(ref: ?*anyopaque) callconv(.c) void {
    const dl: *DeferredLightingModule = @ptrCast(@alignCast(ref orelse return));
    dl.systems.unregister();
    destroyModule(dl);
    gpa.destroy(dl);
}

/// The factory declared in deferred_lighting_create.h. A missing settings, scene, frame, service or
/// device fails as an invalid argument. A failed setup fails with its code and leaves the handle
/// zeroed, after the block is released.
export fn ke_render_deferred_lighting_create(
    service_in: ?*abi_render.c.ke_render_service,
    device_in: ?*abi_render_gpu.c.ke_gpu_device,
    frame_in: ?*abi_render_frame.c.ke_render_frame,
    scene_in: ?*abi_render.c.ke_render_scene_resolve,
    render_queue: ?*abi_schedule.c.ke_schedule,
    render_queue_set: abi_schedule.c.ke_schedule_set_id,
    settings: ?*abi_settings.c.ke_settings,
    out_pass: ?*abi_part.c.ke_owner,
) callconv(.c) abi_result.c.ke_result {
    const out = out_pass orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const values = settings_schema.read(Settings, settings orelse {
        log.warn("deferred lighting: no settings", .{});
        return R.code(error.InvalidArgument);
    }) catch |err| return R.code(err);
    const config = &values;
    const service = service_in orelse return R.code(error.InvalidArgument);
    const device = device_in orelse return R.code(error.InvalidArgument);
    const frame = frame_in orelse return R.code(error.InvalidArgument);
    const scene = scene_in orelse return R.code(error.InvalidArgument);
    if (render_queue == null) return R.code(error.InvalidArgument);

    const dl = gpa.create(DeferredLightingModule) catch |err| return R.code(err);
    dl.* = .{};
    setup(dl, service, device, frame, scene, config) catch |err| {
        destroyModule(dl);
        gpa.destroy(dl);
        return R.code(err);
    };
    const registered = dl.systems.register(.{.{ .name = "render.deferred_lighting", .execute = queueSystem, .user = dl, .hook = 0, .queries = &dl.queries, .access = &dl.access }}, &.{ .{ .schedule = render_queue, .set = render_queue_set } });
    if (registered != R.ok) {
        destroyModule(dl);
        gpa.destroy(dl);
        return registered;
    }
    out.* = .{ .ref = dl, .destroy = destroyOwner };
    return R.ok;
}

const testing = std.testing;
const zsub = @import("zsub");

const test_ids = std.mem.zeroInit(abi_render.c.ke_render_scene_component_ids, .{ .mesh = 1, .camera = 2, .directional_light = 3, .point_light = 4, .spot_light = 5, .ambient_light = 6, .skybox = 7, .sprite2d = 8, .label = 9, .world_transform = 10 });

fn testComponentIds(_: ?*abi_render.c.ke_render_scene_resolve) callconv(.c) ?*const abi_render.c.ke_render_scene_component_ids {
    return &test_ids;
}

var test_scene: abi_render.c.ke_render_scene_resolve = .{ .handle = null, .component_ids = testComponentIds, .render_component_ids = testComponentIds };

var test_camera_component = std.mem.zeroes(abi_render_components.c.ke_camera_component);
var camera_columns = [_]?*anyopaque{ @ptrCast(&test_camera_component), @ptrCast(&test_camera_component) };
var camera_segment: abi_ecs.c.ke_ecs_segment = .{ .entities = null, .count = 1, .columns = &camera_columns, .column_count = 2 };

fn cameraView(_: ?*abi_schedule.c.ke_schedule_ctx, index: u32, out_count: ?*usize) callconv(.c) ?[*]const abi_ecs.c.ke_ecs_segment {
    out_count.?.* = if (index == 0) 1 else 0;
    return if (index == 0) (&camera_segment)[0..1] else null;
}

var camera_ctx: abi_schedule.c.ke_schedule_ctx = .{ .handle = null, .commands = null, .view = cameraView, .slice = null };

fn publishedGbuffer(args: zsub.For(abi_render_frame.c.ke_render_frame).Args(.find)) rg.ke_render_graph_resource {
    const name = std.mem.span(args[1].?);
    return if (std.mem.startsWith(u8, name, "gbuffer.")) 20 else rg.KE_RENDER_GRAPH_RESOURCE_INVALID;
}

/// The parts a pass is made of in a test.
const Rig = struct {
    binder: zsub.For(abi_render_gpu.c.ke_render_resource_binder),
    core: zsub.For(abi_render.c.ke_render_service),
    dev: zsub.For(abi_render_gpu.c.ke_gpu_device),
    schedule: zsub.For(abi_schedule.c.ke_schedule),
    frame: zsub.For(abi_render_frame.c.ke_render_frame),
    graph: zsub.For(rg.ke_render_graph),

    fn init(self: *Rig) !void {
        try self.dev.init();
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
        try self.frame.init();
        _ = self.frame.when(.frame_cid).returns(11);
        _ = self.frame.when(.live).returns(true);
        _ = self.frame.when(.color).returns(2);
        _ = self.frame.when(.depth).returns(4);
        _ = self.frame.when(.find).does(publishedGbuffer);
        _ = self.frame.when(.graph).returns(self.graph.api());
        _ = self.frame.when(.color_format).returns(abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT);
    }

    fn deinit(self: *Rig) void {
        self.frame.deinit();
        self.graph.deinit();
        self.schedule.deinit();
        self.core.deinit();
        self.binder.deinit();
        self.dev.deinit();
    }

    fn create(self: *Rig, settings: ?*abi_settings.c.ke_settings, out: *abi_part.c.ke_owner) abi_result.c.ke_result {
        return ke_render_deferred_lighting_create(self.core.api(), self.dev.api(), self.frame.api(), &test_scene, self.schedule.api(), 4, settings, out);
    }

    fn expectReleased(self: *Rig) !void {
        try self.binder.received(.destroy_shader_layout).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_shader_layout));
        try self.binder.received(.destroy_set).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_set));
    }
};

var test_settings = settings_schema.Fixed.init(&.{});

fn passOf(h: abi_part.c.ke_owner) *DeferredLightingModule {
    return @ptrCast(@alignCast(h.ref.?));
}

test "the deferred lighting pass registers its system in its hook, and destroying it unregisters it and releases the GPU objects" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_part.c.ke_owner = undefined;
    try R.check(rig.create(&test_settings.api, &h));
    try rig.schedule.received(.register_system).times(1);
    h.destroy.?(h.ref);
    try rig.schedule.received(.unregister_system).times(1);
    try rig.expectReleased();
}

test "a camera and a published gbuffer get a lighting pass at the opaque stage" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_part.c.ke_owner = undefined;
    try R.check(rig.create(&test_settings.api, &h));
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, queueSystem(&camera_ctx, passOf(h), 0));
    try rig.graph.received(.add_pass).times(1);
}

test "a frame with no published gbuffer gets no lighting pass" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.frame.when(.find).returns(rg.KE_RENDER_GRAPH_RESOURCE_INVALID);
    var h: abi_part.c.ke_owner = undefined;
    try R.check(rig.create(&test_settings.api, &h));
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, queueSystem(&camera_ctx, passOf(h), 0));
    try rig.graph.received(.add_pass).never();
}

test "a deferred lighting pass whose shader fails to load releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.core.when(.load_shader).returns(abi_result.c.KE_RESULT_GENERAL);
    var h: abi_part.c.ke_owner = undefined;
    try testing.expect(rig.create(&test_settings.api, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
}

test "a deferred lighting pass without a config is refused as an invalid argument" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_part.c.ke_owner = undefined;
    try testing.expectError(error.InvalidArgument, R.check(rig.create(null, &h)));
    try testing.expect(h.ref == null);
}

test "creating and destroying deferred lighting passes leaves no block allocated" {
    try heap.expectNoLeaks();
}
