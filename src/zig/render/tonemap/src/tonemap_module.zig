//! The tonemap pass: the system "render.tonemap" that declares, at the tonemap stage, the pass writing
//! the frame's colour, tonemapped, into the frame's output. It also owns the creation and teardown of
//! that pass, behind the one factory it exports.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_gpu = @import("abi_render_gpu");
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_tonemap").logFn };

const abi_ecs = @import("abi_ecs");
const abi_module = @import("abi_module");
const abi_render = @import("abi_render");
const abi_render_context = @import("abi_render_context");
const abi_render_frame = @import("abi_render_frame");
const abi_render_graph = @import("abi_render_graph");
const abi_result = @import("abi_result");
const abi_schedule = @import("abi_schedule");
const pass_systems = @import("pass_systems");
const R = @import("result").Result(.{});

const heap = @import("heap");
const gpa = heap.gpa;
const rg = abi_render_graph.c;

const shader_layout = abi_render_gpu.c.ke_render_shader_layout_desc{
    .shader = "tonemap",
    .stages = abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT,
    .hints = null,
    .hint_count = 0,
};

/// The state of one tonemap pass. The factory allocates it and `destroyHandle` frees it, after
/// detaching `systems`, whose system receives it as its context. `color` is the frame's colour the
/// pass declared this frame, read by `record`.
const TonemapModule = struct {
    systems: pass_systems.Systems(1) = undefined,
    core: *abi_render.c.ke_render_service = undefined,
    device: *abi_render_gpu.c.ke_gpu_device = undefined,
    frame: *abi_render_frame.c.ke_render_frame = undefined,

    pipeline_params: abi_render_gpu.c.ke_gpu_render_pipeline_desc = undefined,
    binder: *abi_render_gpu.c.ke_render_resource_binder = undefined,
    layout: abi_asset_resolver.c.ke_render_shader_layout = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    set: abi_asset_resolver.c.ke_render_resource_set = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    color: rg.ke_render_graph_resource = rg.KE_RENDER_GRAPH_RESOURCE_INVALID,

    access: [1]abi_ecs.c.ke_ecs_query_term = undefined,
};

const log = std.log.scoped(.render_tonemap);

inline fn moduleOf(user: ?*anyopaque) *TonemapModule {
    return @alignCast(@ptrCast(user.?));
}

/// Records the pass: one full-screen triangle with no vertex input and no depth test, sampling the
/// frame's colour through the shader named "tonemap". It recreates the set every frame, because the
/// colour's view is the graph's for this frame; when the set cannot be created it fails with the
/// binder's code.
fn record(user: ?*anyopaque, ctx: ?*rg.ke_render_graph_ctx) callconv(.c) abi_result.c.ke_result {
    const tm = moduleOf(user);
    const core = tm.core;
    const bindings = [1]abi_render_gpu.c.ke_render_shader_binding{
        .{ .name = "t_hdr", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = ctx.?.texture_view.?(ctx, tm.color), .sampler = 0 },
    };
    tm.binder.destroy_set.?(tm.binder, tm.set);
    const made = tm.binder.create_set.?(tm.binder, tm.layout, null, "tonemap.set", &bindings, bindings.len, &tm.set);
    if (made != R.ok) {
        log.warn("tonemap pass: set creation failed", .{});
        return made;
    }
    const rp: [*c]abi_render_gpu.c.ke_gpu_render_pass = @ptrCast(ctx.?.render_pass.?(ctx));
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &tm.pipeline_params));
    tm.binder.bind_render_set.?(tm.binder, rp, tm.set, null, 0);
    rp.*.draw.?(rp, 3, 1, 0, 0);
    return R.ok;
}

/// "render.tonemap", in the render queue set: declares at KE_RENDER_STAGE_TONEMAP the pass sampling
/// the frame's colour and writing every texel of its output, and claims the output. A frame not
/// being declared gets nothing; the graph refusing the pass fails with its code.
fn queueSystem(_: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const tm = moduleOf(user);
    const frame = tm.frame;
    if (!frame.live.?(frame)) return R.ok;
    tm.color = frame.color.?(frame);
    var uses = std.mem.zeroes([2]rg.ke_render_graph_use);
    uses[0].resource = tm.color;
    uses[0].usage = rg.KE_RENDER_GRAPH_USAGE_SAMPLED;
    uses[1].resource = frame.output.?(frame);
    uses[1].usage = rg.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT;
    uses[1].load = rg.KE_RENDER_GRAPH_LOAD_DONT_CARE;
    var desc = std.mem.zeroes(rg.ke_render_graph_pass_desc);
    desc.name = "render.tonemap";
    desc.type = rg.KE_RENDER_GRAPH_PASS_RASTER;
    desc.injection_point = abi_render.c.KE_RENDER_STAGE_TONEMAP;
    desc.uses = &uses;
    desc.use_count = uses.len;
    desc.record = record;
    desc.user = tm;
    const graph = frame.graph.?(frame).?;
    var pass: rg.ke_render_graph_pass = 0;
    const added = graph.add_pass.?(graph, &desc, &pass);
    if (added != R.ok) return added;
    frame.claim_output.?(frame);
    return R.ok;
}

/// Fills the module during `ke_render_tonemap_create`: builds the pipeline in the format of the
/// frame's output. A failed shader load or layout request fails before the layout exists; after
/// it, a failed pipeline request fails with the layout left for the caller's release. The caller
/// releases the module after any failure. A successful call has asked the service for the pipeline
/// once, so a failure surfaces at creation.
fn setup(tm: *TonemapModule, p: *const abi_render_context.c.ke_render_context) R.Error!void {
    const core: *abi_render.c.ke_render_service = p.service.?;
    tm.core = core;
    tm.device = p.device.?;
    tm.frame = p.frame.?;
    const format = tm.frame.output_format.?(tm.frame);

    var vs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "tonemap", abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX, &vs));
    var fs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "tonemap", abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT, &fs));

    tm.binder = core.*.resource_binder.?(core).?;
    try R.check(tm.binder.create_shader_layout.?(tm.binder, &shader_layout, &tm.layout));
    var pp = std.mem.zeroes(abi_render_gpu.c.ke_gpu_render_pipeline_desc);
    pp.label = "tonemap.pipeline";
    pp.vertex_module   = vs;
    pp.vertex_entry    = "vs_main";
    pp.fragment_module = fs;
    pp.fragment_entry  = "fs_main";
    try R.check(tm.binder.pipeline_layouts.?(tm.binder, tm.layout, &pp.bind_group_layouts, pp.bind_group_layouts.len, &pp.bind_group_layout_count));
    pp.color_target_formats[0] = format;
    pp.color_target_count = 1;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = false;
    pp.depth_stencil.depth_write_enabled = false;
    pp.depth_stencil.depth_compare = abi_render_gpu.c.KE_GPU_COMPARE_ALWAYS;
    tm.pipeline_params = pp;
    if (core.*.get_or_create_pipeline.?(core, &tm.pipeline_params) == abi_render_gpu.c.KE_GPU_INVALID_HANDLE) return error.General;

    tm.access = .{.{ .component = tm.frame.frame_cid.?(tm.frame), .access = abi_ecs.c.KE_ECS_ACCESS_WRITE }};
}

/// Releases the set of the last frame and the layout, each only when it is valid. Runs from
/// `destroyHandle` and from the failure paths of `ke_render_tonemap_create`.
fn destroyModule(tm: *const TonemapModule) void {
    if (tm.layout == abi_render_gpu.c.KE_RENDER_BINDING_INVALID) return;
    tm.binder.destroy_set.?(tm.binder, tm.set);
    tm.binder.destroy_shader_layout.?(tm.binder, tm.layout);
}

/// The `destroy` slot of the handle `ke_render_tonemap_create` returns. It detaches the module,
/// releases the GPU objects and frees the pass; a null argument is ignored.
fn destroyHandle(self: ?*abi_module.c.ke_module) callconv(.c) void {
    const systems: *pass_systems.Systems(1) = @ptrCast(@alignCast((self orelse return).handle));
    const tm: *TonemapModule = @fieldParentPtr("systems", systems);
    pass_systems.Systems(1).detach(self);
    destroyModule(tm);
    gpa.destroy(tm);
}

/// The factory declared in tonemap_create.h. A missing service, device or frame fails as an invalid
/// argument and a failed allocation as out of memory. A failure in `setup` fails with its code and
/// leaves the handle zeroed. On success the handle owns the pass.
export fn ke_render_tonemap_create(context_in: ?*const abi_render_context.c.ke_render_context, out_module: ?*abi_module.c.ke_module_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_module orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_module.c.ke_module_handle);
    const p = context_in orelse return R.code(error.InvalidArgument);
    if (p.service == null or p.device == null or p.frame == null) return R.code(error.InvalidArgument);

    const tm = gpa.create(TonemapModule) catch |err| return R.code(err);
    tm.* = .{};
    setup(tm, p) catch |err| {
        destroyModule(tm);
        gpa.destroy(tm);
        return R.code(err);
    };
    tm.systems.init(.{.{ .name = "render.tonemap", .execute = queueSystem, .user = tm, .set = .queue, .access = &tm.access }});
    out.* = .{ .ref = &tm.systems.module, .destroy = destroyHandle };
    return R.ok;
}

const testing = std.testing;

const zsub = @import("zsub");

var empty_ctx: abi_schedule.c.ke_schedule_ctx = std.mem.zeroes(abi_schedule.c.ke_schedule_ctx);

/// The parts a pass is made of in a test.
const Rig = struct {
    dev: zsub.For(abi_render_gpu.c.ke_gpu_device),
    binder: zsub.For(abi_render_gpu.c.ke_render_resource_binder),
    core: zsub.For(abi_render.c.ke_render_service),
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
        try self.schedule.init();
        _ = self.schedule.when(.register_system).writesFresh(2);
        try self.graph.init();
        try self.frame.init();
        _ = self.frame.when(.frame_cid).returns(11);
        _ = self.frame.when(.live).returns(true);
        _ = self.frame.when(.color).returns(2);
        _ = self.frame.when(.output).returns(3);
        _ = self.frame.when(.graph).returns(self.graph.api());
        _ = self.frame.when(.output_format).returns(abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM);
    }

    fn deinit(self: *Rig) void {
        self.frame.deinit();
        self.graph.deinit();
        self.schedule.deinit();
        self.core.deinit();
        self.binder.deinit();
        self.dev.deinit();
    }

    fn context(self: *Rig) abi_render_context.c.ke_render_context {
        return std.mem.zeroInit(abi_render_context.c.ke_render_context, .{ .service = self.core.api(), .device = self.dev.api(), .frame = self.frame.api() });
    }

    fn targets(self: *Rig) abi_module.c.ke_module_targets {
        var t = std.mem.zeroes(abi_module.c.ke_module_targets);
        t.render = @ptrCast(self.schedule.api());
        return t;
    }

    fn expectReleased(self: *Rig) !void {
        try self.binder.received(.destroy_shader_layout).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_shader_layout));
        try self.binder.received(.destroy_set).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_set));
    }
};

fn passOf(h: abi_module.c.ke_module_handle) *TonemapModule {
    const systems: *pass_systems.Systems(1) = @ptrCast(@alignCast(h.ref.?.handle));
    return @fieldParentPtr("systems", systems);
}

test "the tonemap module attaches its system to the render schedule, and destroying it detaches it and releases the GPU objects" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const p = rig.context();
    var h: abi_module.c.ke_module_handle = undefined;
    try R.check(ke_render_tonemap_create(&p, &h));
    const t = rig.targets();
    try R.check(h.ref.?.attach.?(h.ref, &t));
    try rig.schedule.received(.register_system).times(1);
    h.destroy.?(h.ref);
    try rig.schedule.received(.unregister_system).times(1);
    try rig.expectReleased();
}

test "the tonemap pass writes the frame's output from its colour at the tonemap stage and claims the output" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const p = rig.context();
    var h: abi_module.c.ke_module_handle = undefined;
    try R.check(ke_render_tonemap_create(&p, &h));
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, queueSystem(&empty_ctx, passOf(h), 0));
    try rig.graph.received(.add_pass).times(1);
    try rig.frame.received(.claim_output).times(1);
}

test "a frame not being declared gets no tonemap pass" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.frame.when(.live).returns(false);
    const p = rig.context();
    var h: abi_module.c.ke_module_handle = undefined;
    try R.check(ke_render_tonemap_create(&p, &h));
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, queueSystem(&empty_ctx, passOf(h), 0));
    try rig.graph.received(.add_pass).never();
    try rig.frame.received(.claim_output).never();
}

test "a tonemap module the schedule refuses fails to attach" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.schedule.when(.register_system).returns(abi_result.c.KE_RESULT_OUT_OF_MEMORY);
    const p = rig.context();
    var h: abi_module.c.ke_module_handle = undefined;
    try R.check(ke_render_tonemap_create(&p, &h));
    defer h.destroy.?(h.ref);
    const t = rig.targets();
    try testing.expect(h.ref.?.attach.?(h.ref, &t) != R.ok);
    try rig.schedule.received(.unregister_system).never();
}

test "a tonemap pass whose shader fails to load releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.core.when(.load_shader).returns(abi_result.c.KE_RESULT_GENERAL);
    const p = rig.context();
    var h: abi_module.c.ke_module_handle = undefined;
    try testing.expect(ke_render_tonemap_create(&p, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
}

test "a tonemap pass missing its device is refused as an invalid argument" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var p = rig.context();
    p.device = null;
    var h: abi_module.c.ke_module_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_tonemap_create(&p, &h)));
    try testing.expect(h.ref == null);
}

test "creating and destroying tonemap passes leaves no block allocated" {
    try heap.expectNoLeaks();
}
