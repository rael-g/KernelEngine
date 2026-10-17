//! The deferred lighting pass: the render-phase system that turns the gbuffer targets into lit
//! colour with one full-screen draw and writes the "hdr" target. It also owns the creation and
//! teardown of that pass, behind the one factory it exports.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };
const cimport = @import("cimport.zig");
const c = cimport.c;

const heap = @import("heap");
const gpa = heap.gpa;
const Features = @import("feature_bindings").FeatureBindings(c);

const depth_hint = [_]c.ke_render_binding_hint{.{ .name = "g_depth", .flags = c.KE_RENDER_BINDING_HINT_DEPTH }};

const shader_layout = c.ke_render_shader_layout_params{
    .shader = "deferred_lighting",
    .stages = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT,
    .hints = &depth_hint,
    .hint_count = depth_hint.len,
};

/// The state of one pass, created by `ke_render_deferred_lighting_create` and freed by
/// `destroyHandle`. A handle field stays invalid until `setup` or `system` creates it, and
/// `system` replaces `gbuffer_set` each tick. `queries`, `access` and `io`
/// are handed to the runtime and to `begin_pass` by address, so the block is never copied.
const DeferredLightingModule = struct {
    core: *c.ke_render_service = undefined,
    device: *c.ke_gpu_device = undefined,
    logger: ?*c.ke_logger = null,
    ibl_enabled: bool = true,

    camera_cid: c.ke_component_id = undefined,
    world_transform_cid: c.ke_component_id = undefined,
    skybox_cid: c.ke_component_id = undefined,

    pipeline_params: c.ke_gpu_render_pipeline_params = undefined,
    binder: *c.ke_render_resource_binder = undefined,
    layout: c.ke_render_shader_layout = c.KE_RENDER_BINDING_INVALID,
    frame_set: c.ke_render_resource_set = c.KE_RENDER_BINDING_INVALID,
    gbuffer_set: c.ke_render_resource_set = c.KE_RENDER_BINDING_INVALID,
    env_cubemap: c.ke_texture_handle = .{ .bits = c.KE_HANDLE_NONE },

    reads: [6][*c]const u8 = undefined,
    writes: [1][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
    access: [13]c.ke_component_access = undefined,
    queries_terms: [3]c.ke_component_access = undefined,
    queries: [2]c.ke_query_decl = undefined,
    access_count: u32 = 0,
};

/// Reports a failed GPU call to the logger at error level under the pass's tag, and does nothing
/// without a logger or an error.
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

/// Recreates `frame_set` over the feature bindings: the shadow map and
/// matrix, the environment cubemap and the cluster light lists. The black cube stands in for the environment when `ibl_enabled` is
/// false, and the white texture stands in for the shadow map when the service has none. It runs
/// from `setup`, and from `system` when the sky cubemap changes; the set it replaces is
/// destroyed. A failure is logged and not returned, so `frame_set` then holds what the binder
/// returned.
fn rebuildFrameSet(dl: *DeferredLightingModule) void {
    const core = dl.core;
    const env_view = core.*.texture_view.?(core, dl.env_cubemap);
    const black_cube_view = core.*.texture_view.?(core, .{ .bits = c.KE_HANDLE_NONE });

    const ibl_view = if (dl.ibl_enabled) env_view else black_cube_view;

    var bindings: [Features.count]c.ke_render_shader_binding = undefined;
    Features.fill(core, ibl_view, &bindings);
    dl.binder.destroy_set.?(dl.binder, dl.frame_set);
    var err: ?*c.ke_error = null;
    dl.frame_set = dl.binder.create_set.?(dl.binder, dl.layout, null, "deferred_lighting.frame_set", &bindings, bindings.len, &err);
    if (err != null) logGpuError(dl.logger, err, "deferred frame set");
}

/// The `execute` of the system that `ke_render_deferred_lighting_create` registers in the render
/// phase. It ends the pass on every path that began one. A missing pass returns true without
/// work, and a missing camera returns true after ending an empty pass; neither is a failure. Only
/// a failure to create the G-buffer set sets the error out-parameter and returns false.
/// The camera and the light come from the frame globals the service holds; the sky selects the
/// environment. The G-buffer views are wrapped in a fresh set every tick, because the
/// targets can be recreated.
fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const dl = moduleOf(user);
    const core = dl.core;

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, 0, &cam_segc);

    const pc = core.*.begin_pass.?(core, &dl.io);
    if (pc == null) return true;
    if (cam_segc == 0 or cam_segs[0].count == 0) {
        const rp0 = pc.*.begin_render.?(pc);
        rp0.*.end.?(rp0);
        core.*.end_pass.?(core, pc);
        return true;
    }

    var sky_segc: usize = 0;
    const sky_segs = ctx.?.view.?(ctx, 1, &sky_segc);
    const want_env: c.ke_texture_handle = if (sky_segc != 0 and sky_segs[0].count != 0)
        (@as(*const c.ke_skybox_component, @ptrCast(@alignCast(sky_segs[0].columns[0])))).cubemap
    else
        .{ .bits = c.KE_HANDLE_NONE };
    if (want_env.bits != dl.env_cubemap.bits) {
        dl.env_cubemap = want_env;
        rebuildFrameSet(dl);
    }

    const albedo_view = pc.*.read.?(pc, "gbuffer_albedo");
    const normal_view = pc.*.read.?(pc, "gbuffer_normal");
    const emissive_view = pc.*.read.?(pc, "gbuffer_emissive");
    const depth_view = pc.*.read.?(pc, "depth");
    const gbuffer_bindings = [4]c.ke_render_shader_binding{
        .{ .name = "g_albedo", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = albedo_view, .sampler = 0 },
        .{ .name = "g_normal", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = normal_view, .sampler = 0 },
        .{ .name = "g_emissive", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = emissive_view, .sampler = 0 },
        .{ .name = "g_depth", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = depth_view, .sampler = 0 },
    };
    dl.binder.destroy_set.?(dl.binder, dl.gbuffer_set);
    var err: ?*c.ke_error = null;
    dl.gbuffer_set = dl.binder.create_set.?(dl.binder, dl.layout, "gbuffer", "deferred_lighting.gbuffer_set", &gbuffer_bindings, gbuffer_bindings.len, &err);
    if (dl.gbuffer_set == c.KE_RENDER_BINDING_INVALID) {
        logGpuError(dl.logger, err, "deferred gbuffer set");
        core.*.end_pass.?(core, pc);
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "deferred lighting pass: gbuffer set creation failed", @src().file, @intCast(@src().line), err);
        return false;
    }

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &dl.pipeline_params));
    dl.binder.bind_render_set.?(dl.binder, rp, dl.frame_set, null, 0);
    dl.binder.bind_render_set.?(dl.binder, rp, dl.gbuffer_set, null, 0);
    rp.*.draw.?(rp, 3, 1, 0, 0);
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
    return true;
}

/// Called once by `ke_render_deferred_lighting_create` on a freshly reset block. It returns true
/// only when every object it creates exists, the pipeline included, and the io, access list and
/// queries are filled. On false, the objects already created stay in the block for the caller to
/// release through `destroyModule`.
fn setup(dl: *DeferredLightingModule, dev: *c.ke_gpu_device, core: *c.ke_render_service,
         logger: ?*c.ke_logger, ibl_enabled: bool,
         camera_cid: c.ke_component_id, world_transform_cid: c.ke_component_id,
         skybox_cid: c.ke_component_id, frame_cid: c.ke_component_id,
         out_error: [*c][*c]c.ke_error) bool {
    dl.core = core;
    dl.device = dev;
    dl.logger = logger;
    dl.ibl_enabled = ibl_enabled;
    dl.camera_cid = camera_cid;
    dl.world_transform_cid = world_transform_cid;
    dl.skybox_cid = skybox_cid;
    dl.env_cubemap = .{ .bits = c.KE_HANDLE_NONE };

    dl.binder = core.*.resource_binder.?(core);
    dl.layout = dl.binder.create_shader_layout.?(dl.binder, &shader_layout, out_error);
    if (dl.layout == c.KE_RENDER_BINDING_INVALID) return false;

    const vs = core.*.load_shader.?(core, "deferred_lighting", c.KE_GPU_SHADER_STAGE_VERTEX, out_error);
    if (vs == c.KE_GPU_INVALID_HANDLE) return false;
    const fs = core.*.load_shader.?(core, "deferred_lighting", c.KE_GPU_SHADER_STAGE_FRAGMENT, out_error);
    if (fs == c.KE_GPU_INVALID_HANDLE) return false;

    var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    pp.label = "deferred_lighting.pipeline";
    pp.vertex_module = vs;
    pp.fragment_module = fs;
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    pp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = 0;
    pp.depth_stencil.depth_write_enabled = 0;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
    if (!dl.binder.pipeline_layouts.?(dl.binder, dl.layout, &pp.bind_group_layouts, pp.bind_group_layouts.len, &pp.bind_group_layout_count, out_error)) return false;
    pp.color_target_formats[0] = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
    pp.color_target_count = 1;
    dl.pipeline_params = pp;
    if (core.*.get_or_create_pipeline.?(core, &dl.pipeline_params) == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "deferred lighting: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    rebuildFrameSet(dl);

    const hdr_cid = core.*.declare.?(core, &c.ke_render_resource_params{
        .name = "hdr",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0, .height = 0, .scale_x = 1.0, .scale_y = 1.0,
    }, null);

    const shadow_map_cid = core.*.cid.?(core, "shadow_map");
    const shadow_enabled = shadow_map_cid != c.KE_COMPONENT_INVALID;
    const cluster_lights_cid = core.*.cid.?(core, "light_clusters");

    dl.writes = .{"hdr"};
    dl.reads = .{ "gbuffer_albedo", "gbuffer_normal", "gbuffer_emissive", "depth", "shadow_map", "light_clusters" };
    dl.io = std.mem.zeroes(c.ke_render_pass_io);
    dl.io.name = "render.deferred_lighting";
    dl.io.writes = @ptrCast(&dl.writes);
    dl.io.writes_count = 1;
    dl.io.reads = @ptrCast(&dl.reads);
    dl.io.reads_count = if (shadow_enabled) 6 else 5;

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
    dl.access[ac] = .{ .cid = world_transform_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = skybox_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = frame_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access_count = ac;

    const rd = c.KE_ACCESS_READ;
    dl.queries_terms = .{ .{ .cid = camera_cid, .access = rd }, .{ .cid = world_transform_cid, .access = rd }, .{ .cid = skybox_cid, .access = rd } };
    dl.queries = .{ .{ .terms = &dl.queries_terms[0], .term_count = 2 }, .{ .terms = &dl.queries_terms[2], .term_count = 1 } };
    return true;
}

/// Releases the sets and the layout the block holds, those still invalid skipped. It leaves the
/// pipeline, the shader modules and the "hdr" resource alone, and does not free the block, so it
/// can release a partly built one.
fn destroyModule(dl: *const DeferredLightingModule) void {
    if (dl.layout == c.KE_RENDER_BINDING_INVALID) return;
    dl.binder.destroy_set.?(dl.binder, dl.gbuffer_set);
    dl.binder.destroy_set.?(dl.binder, dl.frame_set);
    dl.binder.destroy_shader_layout.?(dl.binder, dl.layout);
}

/// The `destroy` slot of the handle that `ke_render_deferred_lighting_create` returns. It releases
/// the GPU objects and then frees the block.
fn destroyHandle(self: ?*c.ke_render_deferred_lighting) callconv(.c) void {
    const dl: *DeferredLightingModule = @ptrCast(@alignCast(self orelse return));
    destroyModule(dl);
    gpa.destroy(dl);
}

/// Builds the pass and registers its system in the render phase, with `pinned_thread` set to zero.
/// On success the handle's `ref` is the block and its `destroy` is `destroyHandle`. A null
/// argument returns an empty handle. A failed setup or a refused registration also returns an
/// empty handle, after the block is released; errors those steps report go to the error
/// out-parameter.
export fn ke_render_deferred_lighting_create(runtime: ?*c.ke_runtime, core: ?*c.ke_render_service,
                                              device: ?*c.ke_gpu_device,
                                              logger: ?*c.ke_logger, ibl_enabled: c.ke_bool,
                                              camera_cid: c.ke_component_id, world_transform_cid: c.ke_component_id,
                                              skybox_cid: c.ke_component_id, frame_cid: c.ke_component_id,
                                              out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_deferred_lighting_handle {
    const empty = c.ke_render_deferred_lighting_handle{ .ref = null, .destroy = null };
    const rt = runtime orelse return empty;
    const core_ref = core orelse return empty;
    const dev = device orelse return empty;

    const dl = gpa.create(DeferredLightingModule) catch return empty;
    dl.* = .{};
    if (!setup(dl, dev, core_ref, logger, ibl_enabled != 0,
               camera_cid, world_transform_cid, skybox_cid, frame_cid, out_error))
    {
        destroyModule(dl);
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
    if (rt.register_system.?(rt, &params, out_error) == 0) {
        destroyModule(dl);
        gpa.destroy(dl);
        return empty;
    }

    return .{ .ref = @ptrCast(dl), .destroy = destroyHandle };
}

const testing = std.testing;

const Stubs = @import("stubs").Stubs(c);

test "creating and destroying the deferred lighting pass leaves no block allocated and no GPU resource live" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    const h = ke_render_deferred_lighting_create(rt.api(), core.api(), dev.api(), null, 0, 1, 2, 3, 4, null);
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a deferred lighting pass whose shader fails to load releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    core.shader_loads_fail = true;
    var rt: Stubs.Runtime = undefined;
    rt.init();
    const h = ke_render_deferred_lighting_create(rt.api(), core.api(), dev.api(), null, 0, 1, 2, 3, 4, null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a deferred lighting pass the runtime refuses to register releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    rt.limit = 0;
    const h = ke_render_deferred_lighting_create(rt.api(), core.api(), dev.api(), null, 0, 1, 2, 3, 4, null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}
