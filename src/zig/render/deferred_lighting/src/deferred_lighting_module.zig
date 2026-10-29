//! The deferred lighting pass: the render-phase system that turns the gbuffer targets into lit
//! colour with one full-screen draw over the frame's color, at the chain's opaque stage. It also owns the creation and
//! teardown of that pass, behind the one factory it exports.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_deferred_lighting").logFn };

const abi_ecs = @import("abi_ecs");
const abi_render = @import("abi_render");
const abi_render_deferred_lighting_factory = @import("abi_render_deferred_lighting_factory");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const R = @import("result").Result(.{});

const heap = @import("heap");
const gpa = heap.gpa;
const Features = @import("feature_bindings");

const depth_hint = [_]abi_render.ke_render_binding_hint{.{ .name = "g_depth", .flags = abi_render.KE_RENDER_BINDING_HINT_DEPTH }};

const shader_layout = abi_render.ke_render_shader_layout_params{
    .shader = "deferred_lighting",
    .stages = abi_render.KE_GPU_SHADER_STAGE_VERTEX | abi_render.KE_GPU_SHADER_STAGE_FRAGMENT,
    .hints = &depth_hint,
    .hint_count = depth_hint.len,
};

/// The state of one pass, created by `ke_render_deferred_lighting_create` and freed by
/// `destroyHandle`. A handle field stays invalid until `setup` or `system` creates it, and
/// `system` replaces `gbuffer_set` each tick. `queries`, `access` and `io`
/// are handed to the runtime and to `begin_pass` by address, so the block is never copied.
/// `destroyHandle` unregisters the system the factory registered before it frees the module.
const DeferredLightingModule = struct {
    runtime: *abi_runtime.ke_runtime = undefined,
    system: abi_runtime.ke_system_id = 0,
    core: *abi_render.ke_render_service = undefined,
    device: *abi_render.ke_gpu_device = undefined,
    ibl_enabled: bool = true,

    camera_cid: abi_ecs.ke_component_id = undefined,
    world_transform_cid: abi_ecs.ke_component_id = undefined,
    skybox_cid: abi_ecs.ke_component_id = undefined,

    albedo: ?[:0]u8 = null,
    normal: ?[:0]u8 = null,
    emissive: ?[:0]u8 = null,
    shadow: ?[:0]u8 = null,
    clusters: ?[:0]u8 = null,

    pipeline_params: abi_render.ke_gpu_render_pipeline_params = undefined,
    binder: *abi_render.ke_render_resource_binder = undefined,
    layout: abi_render.ke_render_shader_layout = abi_render.KE_RENDER_BINDING_INVALID,
    frame_set: abi_render.ke_render_resource_set = abi_render.KE_RENDER_BINDING_INVALID,
    gbuffer_set: abi_render.ke_render_resource_set = abi_render.KE_RENDER_BINDING_INVALID,
    env_cubemap: abi_render.ke_texture_handle = .{ .bits = abi_render.KE_HANDLE_NONE },

    io: abi_render.ke_render_pass_io = std.mem.zeroes(abi_render.ke_render_pass_io),
    access: [13]abi_runtime.ke_component_access = undefined,
    queries_terms: [3]abi_runtime.ke_component_access = undefined,
    queries: [2]abi_runtime.ke_query_decl = undefined,
    access_count: u32 = 0,
};

const log = std.log.scoped(.render_deferred_lighting);

inline fn moduleOf(user: ?*anyopaque) *DeferredLightingModule {
    return @alignCast(@ptrCast(user.?));
}

/// Recreates `frame_set` over the feature bindings: the shadow map and
/// matrix, the environment cubemap and the cluster light lists. The black cube stands in for the
/// environment when `ibl_enabled` is false, and the white texture for the shadow map when the pass
/// was given no shadow group or the group published none. It runs
/// from `setup`, and from `system` when the sky cubemap changes; the set it replaces is
/// destroyed. A failure is logged and not returned, and `frame_set` is then invalid.
fn rebuildFrameSet(dl: *DeferredLightingModule) void {
    const core = dl.core;
    const env_view = core.*.texture_view.?(core, dl.env_cubemap);
    const black_cube_view = core.*.texture_view.?(core, .{ .bits = abi_render.KE_HANDLE_NONE });

    const ibl_view = if (dl.ibl_enabled) env_view else black_cube_view;

    var bindings: [Features.count]abi_render.ke_render_shader_binding = undefined;
    Features.fill(core, ibl_view, nameOf(dl.shadow), nameOf(dl.clusters), &bindings);
    dl.binder.destroy_set.?(dl.binder, dl.frame_set);
    if (dl.binder.create_set.?(dl.binder, dl.layout, null, "deferred_lighting.frame_set", &bindings, bindings.len, &dl.frame_set) != R.ok)
        log.err("deferred frame set creation failed", .{});
}

/// The `execute` of the system that `ke_render_deferred_lighting_create` registers in the render
/// phase. It ends the pass on every path that began one. A missing pass succeeds without work,
/// and a missing camera succeeds after ending an empty pass. Only a failure to create the
/// G-buffer set fails, with the binder's code.
/// The camera and the light come from the frame globals the service holds; the sky selects the
/// environment. The G-buffer views are wrapped in a fresh set every tick, because the
/// targets can be recreated.
fn system(ctx: ?*abi_runtime.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const dl = moduleOf(user);
    const core = dl.core;

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, 0, &cam_segc);

    const pc = core.*.begin_pass.?(core, &dl.io);
    if (pc == null) return R.ok;
    if (cam_segc == 0 or cam_segs.?[0].count == 0) {
        const rp0 = pc.?.begin_render.?(pc);
        rp0.?.end.?(rp0);
        core.*.end_pass.?(core, pc);
        return R.ok;
    }

    var sky_segc: usize = 0;
    const sky_segs = ctx.?.view.?(ctx, 1, &sky_segc);
    const want_env: abi_render.ke_texture_handle = if (sky_segc != 0 and sky_segs.?[0].count != 0)
        (@as(*const abi_render.ke_skybox_component, @ptrCast(@alignCast(sky_segs.?[0].columns.?[0])))).cubemap
    else
        .{ .bits = abi_render.KE_HANDLE_NONE };
    if (want_env.bits != dl.env_cubemap.bits) {
        dl.env_cubemap = want_env;
        rebuildFrameSet(dl);
    }

    const albedo_view = pc.?.read.?(pc, dl.albedo.?.ptr);
    const normal_view = pc.?.read.?(pc, dl.normal.?.ptr);
    const emissive_view = pc.?.read.?(pc, dl.emissive.?.ptr);
    const depth_view = pc.?.read.?(pc, abi_render.KE_RENDER_FRAME_DEPTH);
    const gbuffer_bindings = [4]abi_render.ke_render_shader_binding{
        .{ .name = "g_albedo", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = albedo_view, .sampler = 0 },
        .{ .name = "g_normal", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = normal_view, .sampler = 0 },
        .{ .name = "g_emissive", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = emissive_view, .sampler = 0 },
        .{ .name = "g_depth", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = depth_view, .sampler = 0 },
    };
    dl.binder.destroy_set.?(dl.binder, dl.gbuffer_set);
    const made = dl.binder.create_set.?(dl.binder, dl.layout, "gbuffer", "deferred_lighting.gbuffer_set", &gbuffer_bindings, gbuffer_bindings.len, &dl.gbuffer_set);
    if (made != R.ok) {
        core.*.end_pass.?(core, pc);
        log.warn("deferred lighting pass: gbuffer set creation failed", .{});
        return made;
    }

    const rp = pc.?.begin_render.?(pc);
    rp.?.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &dl.pipeline_params));
    dl.binder.bind_render_set.?(dl.binder, rp, dl.frame_set, null, 0);
    dl.binder.bind_render_set.?(dl.binder, rp, dl.gbuffer_set, null, 0);
    rp.?.draw.?(rp, 3, 1, 0, 0);
    rp.?.end.?(rp);
    core.*.end_pass.?(core, pc);
    return R.ok;
}

/// Called once by `ke_render_deferred_lighting_create` on a freshly reset block. It succeeds only
/// when every object it creates exists, the pipeline included, and the io, access list and
/// queries are filled. On failure, the objects already created stay in the block for the caller to
/// release through `destroyModule`.
/// Joining, it tells the runtime that the chain, not the runtime, orders the writers of the
/// frame's color.
fn setup(dl: *DeferredLightingModule, p: *const abi_render_deferred_lighting_factory.ke_render_deferred_lighting_params) R.Error!void {
    const core: *abi_render.ke_render_service = p.service.?;
    const camera_cid = p.camera_cid;
    const world_transform_cid = p.world_transform_cid;
    const skybox_cid = p.skybox_cid;
    const frame_cid = p.frame_cid;
    dl.core = core;
    dl.device = p.device.?;
    dl.ibl_enabled = p.ibl_enabled;
    dl.camera_cid = camera_cid;
    dl.world_transform_cid = world_transform_cid;
    dl.skybox_cid = skybox_cid;
    dl.env_cubemap = .{ .bits = abi_render.KE_HANDLE_NONE };

    const group = std.mem.span(p.gbuffer.?);
    dl.albedo = std.fmt.allocPrintSentinel(gpa, "{s}{s}", .{ group, abi_render.KE_RENDER_GBUFFER_ALBEDO }, 0) catch return error.OutOfMemory;
    dl.normal = std.fmt.allocPrintSentinel(gpa, "{s}{s}", .{ group, abi_render.KE_RENDER_GBUFFER_NORMAL }, 0) catch return error.OutOfMemory;
    dl.emissive = std.fmt.allocPrintSentinel(gpa, "{s}{s}", .{ group, abi_render.KE_RENDER_GBUFFER_EMISSIVE }, 0) catch return error.OutOfMemory;
    dl.io.name = "render.deferred_lighting";
    try R.check(core.*.join_chain.?(core, abi_render.KE_RENDER_STAGE_OPAQUE, abi_render.KE_RENDER_CHAIN_DRAW_OVER, &dl.io.chain));
    try R.check(p.runtime.?.declare_self_ordered.?(p.runtime, core.*.cid.?(core, abi_render.KE_RENDER_FRAME_COLOR)));
    if (p.shadow != null) dl.shadow = gpa.dupeZ(u8, std.mem.span(p.shadow.?)) catch return error.OutOfMemory;
    if (p.clusters != null) dl.clusters = gpa.dupeZ(u8, std.mem.span(p.clusters.?)) catch return error.OutOfMemory;

    dl.binder = core.*.resource_binder.?(core).?;
    try R.check(dl.binder.create_shader_layout.?(dl.binder, &shader_layout, &dl.layout));

    var vs: abi_render.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "deferred_lighting", abi_render.KE_GPU_SHADER_STAGE_VERTEX, &vs));
    var fs: abi_render.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "deferred_lighting", abi_render.KE_GPU_SHADER_STAGE_FRAGMENT, &fs));

    var pp = std.mem.zeroes(abi_render.ke_gpu_render_pipeline_params);
    pp.label = "deferred_lighting.pipeline";
    pp.vertex_module = vs;
    pp.fragment_module = fs;
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = abi_render.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = abi_render.KE_GPU_CULL_MODE_NONE;
    pp.front_face = abi_render.KE_GPU_FRONT_FACE_CCW;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = false;
    pp.depth_stencil.depth_write_enabled = false;
    pp.depth_stencil.depth_compare = abi_render.KE_GPU_COMPARE_ALWAYS;
    try R.check(dl.binder.pipeline_layouts.?(dl.binder, dl.layout, &pp.bind_group_layouts, pp.bind_group_layouts.len, &pp.bind_group_layout_count));
    pp.color_target_formats[0] = core.*.chain_format.?(core, abi_render.KE_RENDER_STAGE_OPAQUE);
    pp.color_target_count = 1;
    dl.pipeline_params = pp;
    if (core.*.get_or_create_pipeline.?(core, &dl.pipeline_params) == abi_render.KE_GPU_INVALID_HANDLE) {
        log.warn("deferred lighting: render pipeline creation failed", .{});
        return error.NotInitialized;
    }

    rebuildFrameSet(dl);

    var ac: u32 = 0;
    dl.access[ac] = .{ .cid = core.*.cid.?(core, abi_render.KE_RENDER_FRAME_COLOR), .access = abi_runtime.KE_ACCESS_WRITE };
    ac += 1;
    for ([_]?[:0]u8{ dl.albedo, dl.normal, dl.emissive, dl.shadow, dl.clusters }) |name| {
        const n = name orelse continue;
        dl.access[ac] = .{ .cid = core.*.cid.?(core, n.ptr), .access = abi_runtime.KE_ACCESS_READ };
        ac += 1;
    }
    dl.access[ac] = .{ .cid = core.*.cid.?(core, abi_render.KE_RENDER_FRAME_DEPTH), .access = abi_runtime.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = camera_cid, .access = abi_runtime.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = world_transform_cid, .access = abi_runtime.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = skybox_cid, .access = abi_runtime.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = frame_cid, .access = abi_runtime.KE_ACCESS_READ };
    ac += 1;
    dl.access_count = ac;

    const rd = abi_runtime.KE_ACCESS_READ;
    dl.queries_terms = .{ .{ .cid = camera_cid, .access = rd }, .{ .cid = world_transform_cid, .access = rd }, .{ .cid = skybox_cid, .access = rd } };
    dl.queries = .{ .{ .terms = dl.queries_terms[0..].ptr, .term_count = 2 }, .{ .terms = dl.queries_terms[2..].ptr, .term_count = 1 } };
}

/// Gives the link back and releases the names, the sets and the layout the block holds, those still
/// absent skipped. It leaves the pipeline and the shader modules alone, and does not free the
/// block, so it can release a partly built one.
fn destroyModule(dl: *const DeferredLightingModule) void {
    if (dl.io.chain != abi_render.KE_RENDER_CHAIN_NONE) dl.core.*.leave_chain.?(dl.core, dl.io.chain);
    for ([_]?[:0]u8{ dl.albedo, dl.normal, dl.emissive, dl.shadow, dl.clusters }) |name| if (name) |n| gpa.free(n);
    if (dl.layout == abi_render.KE_RENDER_BINDING_INVALID) return;
    dl.binder.destroy_set.?(dl.binder, dl.gbuffer_set);
    dl.binder.destroy_set.?(dl.binder, dl.frame_set);
    dl.binder.destroy_shader_layout.?(dl.binder, dl.layout);
}

/// The `destroy` slot of the handle that `ke_render_deferred_lighting_create` returns. It releases
/// the GPU objects and then frees the block.
fn destroyHandle(self: ?*abi_render_deferred_lighting_factory.ke_render_deferred_lighting) callconv(.c) void {
    const dl: *DeferredLightingModule = @ptrCast(@alignCast(self orelse return));
    _ = dl.runtime.unregister_system.?(dl.runtime, dl.system);
    destroyModule(dl);
    gpa.destroy(dl);
}

/// Builds the pass and registers its system in the render phase.
/// On success the handle's `ref` is the block and its `destroy` is `destroyHandle`. A missing
/// runtime, service, device or gbuffer fails as an invalid argument. A failed setup or a refused
/// registration fails with its code and leaves the handle zeroed, after the block is released.
export fn ke_render_deferred_lighting_create(params_in: ?*const abi_render_deferred_lighting_factory.ke_render_deferred_lighting_params, out_lighting: [*c]abi_render_deferred_lighting_factory.ke_render_deferred_lighting_handle) callconv(.c) abi_result.ke_result {
    const out = out_lighting orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const p = params_in orelse return R.code(error.InvalidArgument);
    const rt: *abi_runtime.ke_runtime = p.runtime orelse return R.code(error.InvalidArgument);
    if (p.service == null or p.device == null or p.gbuffer == null)
        return R.code(error.InvalidArgument);

    const dl = gpa.create(DeferredLightingModule) catch |err| return R.code(err);
    dl.* = .{};
    setup(dl, p) catch |err| {
        destroyModule(dl);
        gpa.destroy(dl);
        return R.code(err);
    };

    var params = std.mem.zeroes(abi_runtime.ke_runtime_system_params);
    params.name = "render.deferred_lighting";
    params.phase = abi_runtime.KE_PHASE_RENDER;
    params.queries = &dl.queries;
    params.query_count = dl.queries.len;
    params.access_list = &dl.access;
    params.access_count = dl.access_count;
    params.user_data = dl;
    params.execute = system;
    var system_id: abi_runtime.ke_system_id = 0;
    const registered = rt.register_system.?(rt, &params, &system_id);
    if (registered != R.ok) {
        destroyModule(dl);
        gpa.destroy(dl);
        return registered;
    }
    dl.runtime = rt;
    dl.system = system_id;

    out.* = .{ .ref = @ptrCast(dl), .destroy = destroyHandle };
    return R.ok;
}


fn nameOf(name: ?[:0]u8) ?[*:0]const u8 {
    return if (name) |n| n.ptr else null;
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
        try self.binder.init();
        _ = self.binder.when(.create_shader_layout).writesFresh(2);
        _ = self.binder.when(.create_set).writesFresh(6);
        try self.core.init();
        _ = self.core.when(.resource_binder).returns(self.binder.api());
        _ = self.core.when(.load_shader).writesFresh(3);
        _ = self.core.when(.get_or_create_pipeline).returnsFresh();
        _ = self.core.when(.cid).returnsFresh();
        _ = self.core.when(.resource_view).returnsFresh();
        _ = self.core.when(.texture_view).returnsFresh();
        _ = self.core.when(.white_texture).returns(.{ .bits = 1 });
        _ = self.core.when(.resource_buffer).returnsFresh();
        _ = self.core.when(.resource_buffer_size).returns(256);
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
        try self.binder.received(.destroy_shader_layout).where(zsub.argIsNot(1, abi_render.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_shader_layout));
        try self.binder.received(.destroy_set).where(zsub.argIsNot(1, abi_render.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_set));
        try self.core.received(.leave_chain).sameAs(self.core.received(.join_chain));
    }
};

fn chainFormat(args: zsub.For(abi_render.ke_render_service).Args(.chain_format)) abi_render.ke_gpu_texture_format {
    return if (args[1] >= abi_render.KE_RENDER_STAGE_TONEMAP) abi_render.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM else abi_render.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
}

test "creating and destroying the deferred lighting pass leaves no block allocated and no GPU resource live" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_render_deferred_lighting_factory.ke_render_deferred_lighting_handle = undefined;
    try R.check(ke_render_deferred_lighting_create(&.{ .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .ibl_enabled = false, .camera_cid = 1, .world_transform_cid = 2, .skybox_cid = 3, .frame_cid = 4, .gbuffer = "gbuffer", .shadow = "shadow", .clusters = "clusters" }, &h));
    h.destroy.?(h.ref);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}

test "destroying the deferred lighting pass unregisters every system it registered" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_render_deferred_lighting_factory.ke_render_deferred_lighting_handle = undefined;
    try R.check(ke_render_deferred_lighting_create(&.{ .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .ibl_enabled = false, .camera_cid = 1, .world_transform_cid = 2, .skybox_cid = 3, .frame_cid = 4, .gbuffer = "gbuffer", .shadow = "shadow", .clusters = "clusters" }, &h));
    h.destroy.?(h.ref);
    try rig.rt.received(.register_system).atLeast(1);
    try rig.rt.received(.unregister_system).where(zsub.argIs(1, @as(abi_runtime.ke_system_id, 0))).never();
    try rig.rt.received(.unregister_system).sameAs(rig.rt.received(.register_system));
}

test "a deferred lighting pass whose shader fails to load releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.core.when(.load_shader).returns(abi_result.KE_RESULT_GENERAL);
    var h: abi_render_deferred_lighting_factory.ke_render_deferred_lighting_handle = undefined;
    try testing.expect(ke_render_deferred_lighting_create(&.{ .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .ibl_enabled = false, .camera_cid = 1, .world_transform_cid = 2, .skybox_cid = 3, .frame_cid = 4, .gbuffer = "gbuffer", .shadow = "shadow", .clusters = "clusters" }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}

test "a deferred lighting pass the runtime refuses to register releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.rt.when(.register_system).returns(abi_result.KE_RESULT_OUT_OF_MEMORY);
    var h: abi_render_deferred_lighting_factory.ke_render_deferred_lighting_handle = undefined;
    try testing.expect(ke_render_deferred_lighting_create(&.{ .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .ibl_enabled = false, .camera_cid = 1, .world_transform_cid = 2, .skybox_cid = 3, .frame_cid = 4, .gbuffer = "gbuffer", .shadow = "shadow", .clusters = "clusters" }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}
