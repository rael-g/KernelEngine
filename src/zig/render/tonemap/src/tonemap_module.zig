//! The tonemap pass: the render-phase system "render.tonemap" that replaces the frame's HDR color
//! with its tonemapped copy, at the chain's tonemap stage. It also owns the creation and teardown
//! of that pass, behind the one factory it exports.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_tonemap").logFn };

const c = @import("c");
const R = @import("result").Result(c, .{});

const heap = @import("heap");
const gpa = heap.gpa;

const shader_layout = c.ke_render_shader_layout_params{
    .shader = "tonemap",
    .stages = c.KE_GPU_SHADER_STAGE_FRAGMENT,
    .hints = null,
    .hint_count = 0,
};

/// The state of one tonemap pass. The factory allocates it and `destroyHandle` frees it. The
/// runtime receives it as the context of `system` at registration. `io` carries the link the pass
/// holds in the chain, given back when the module is destroyed.
pub const TonemapModule = struct {
    core: *c.ke_render_service = undefined,
    device: *c.ke_gpu_device = undefined,

    pipeline_params: c.ke_gpu_render_pipeline_params = undefined,
    binder: *c.ke_render_resource_binder = undefined,
    layout: c.ke_render_shader_layout = c.KE_RENDER_BINDING_INVALID,
    set: c.ke_render_resource_set = c.KE_RENDER_BINDING_INVALID,

    io: c.ke_render_pass_io = std.mem.zeroes(c.ke_render_pass_io),
    access: [2]c.ke_component_access = undefined,
};

const log = std.log.scoped(.render_tonemap);

inline fn moduleOf(user: ?*anyopaque) *TonemapModule {
    return @alignCast(@ptrCast(user.?));
}

/// The render-phase body that `ke_render_tonemap_create` registers, called by the runtime with the
/// module as its context. A frame in which the service begins no pass succeeds without drawing.
/// When the set cannot be created, the pass is ended and the body fails with the binder's code.
/// Each frame it draws one full-screen triangle with no vertex input and no depth test, sampling
/// the color source of its link through the shader named "tonemap". It recreates the set every
/// frame, because the source's view is read from the pass each time.
fn system(_: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) c.ke_result {
    const tm = moduleOf(user);
    const core = tm.core;

    const pc = core.*.begin_pass.?(core, &tm.io);
    if (pc == null) return R.ok;

    const hdr_view = pc.*.color_source.?(pc);
    const bindings = [1]c.ke_render_shader_binding{
        .{ .name = "t_hdr", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = hdr_view, .sampler = 0 },
    };
    tm.binder.destroy_set.?(tm.binder, tm.set);
    const made = tm.binder.create_set.?(tm.binder, tm.layout, null, "tonemap.set", &bindings, bindings.len, &tm.set);
    if (made != R.ok) {
        core.*.end_pass.?(core, pc);
        log.warn("tonemap pass: set creation failed", .{});
        return made;
    }

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &tm.pipeline_params));
    tm.binder.bind_render_set.?(tm.binder, rp, tm.set, null, 0);
    rp.*.draw.?(rp, 3, 1, 0, 0);
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
    return R.ok;
}

/// Fills the module during `ke_render_tonemap_create`, before `system` is registered: joins the
/// chain and builds the pipeline in the format of the tonemap stage. A failed join, shader load or
/// layout request fails before the layout exists; after it, a failed pipeline request fails with
/// the layout left for the caller's release. The caller releases the module after any failure. A
/// successful call has asked the service for the pipeline once, so a
/// failure surfaces at creation.
/// Joining, it tells the runtime that the chain, not the runtime, orders the writers of the
/// frame's color.
fn setup(tm: *TonemapModule, p: *const c.ke_render_tonemap_params) R.Error!void {
    const core: *c.ke_render_service = p.service;
    tm.core = core;
    tm.device = p.device;

    tm.io.name = "render.tonemap";
    try R.check(core.*.join_chain.?(core, c.KE_RENDER_STAGE_TONEMAP, c.KE_RENDER_CHAIN_REPLACE, &tm.io.chain));
    try R.check(p.runtime.*.declare_self_ordered.?(p.runtime, core.*.cid.?(core, c.KE_RENDER_FRAME_COLOR)));
    const format = core.*.chain_format.?(core, c.KE_RENDER_STAGE_TONEMAP);

    var vs: c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "tonemap", c.KE_GPU_SHADER_STAGE_VERTEX, &vs));
    var fs: c.ke_gpu_shader_module = undefined;
    try R.check(core.*.load_shader.?(core, "tonemap", c.KE_GPU_SHADER_STAGE_FRAGMENT, &fs));

    tm.binder = core.*.resource_binder.?(core);
    try R.check(tm.binder.create_shader_layout.?(tm.binder, &shader_layout, &tm.layout));
    var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
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
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
    tm.pipeline_params = pp;
    if (core.*.get_or_create_pipeline.?(core, &tm.pipeline_params) == c.KE_GPU_INVALID_HANDLE) return error.General;

    tm.access = .{
        .{ .cid = core.*.cid.?(core, c.KE_RENDER_FRAME_COLOR), .access = c.KE_ACCESS_WRITE },
        .{ .cid = p.frame_cid, .access = c.KE_ACCESS_READ },
    };
}

/// Gives the link back and releases the set of the last frame and the layout, each only when it is
/// valid. Runs from `destroyHandle` and from the failure paths of `ke_render_tonemap_create`.
fn destroyModule(tm: *const TonemapModule) void {
    if (tm.io.chain != c.KE_RENDER_CHAIN_NONE) tm.core.*.leave_chain.?(tm.core, tm.io.chain);
    if (tm.layout == c.KE_RENDER_BINDING_INVALID) return;
    tm.binder.destroy_set.?(tm.binder, tm.set);
    tm.binder.destroy_shader_layout.?(tm.binder, tm.layout);
}

/// The `destroy` slot of the handle `ke_render_tonemap_create` returns. It releases the GPU objects
/// and frees the module; a null argument is ignored.
fn destroyHandle(self: ?*c.ke_render_tonemap) callconv(.c) void {
    const tm: *TonemapModule = @ptrCast(@alignCast(self orelse return));
    destroyModule(tm);
    gpa.destroy(tm);
}

/// The factory declared in tonemap_create.h. A missing runtime, service or device fails as an
/// invalid argument and a failed allocation as out of memory. A failure in `setup`, or the runtime
/// refusing `system`, fails with its code and leaves the handle zeroed. On success the runtime
/// holds the module as the context of `system`, and the handle frees it.
export fn ke_render_tonemap_create(params_in: ?*const c.ke_render_tonemap_params, out_tonemap: [*c]c.ke_render_tonemap_handle) callconv(.c) c.ke_result {
    const out = out_tonemap orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const p = params_in orelse return R.code(error.InvalidArgument);
    const rt: *c.ke_runtime = p.runtime orelse return R.code(error.InvalidArgument);
    if (p.service == null or p.device == null) return R.code(error.InvalidArgument);

    const tm = gpa.create(TonemapModule) catch |err| return R.code(err);
    tm.* = .{};
    register(tm, p, rt) catch |err| {
        destroyModule(tm);
        gpa.destroy(tm);
        return R.code(err);
    };
    out.* = .{ .ref = @ptrCast(tm), .destroy = destroyHandle };
    return R.ok;
}

fn register(tm: *TonemapModule, p: *const c.ke_render_tonemap_params, rt: *c.ke_runtime) R.Error!void {
    try setup(tm, p);
    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = "render.tonemap";
    params.phase = c.KE_PHASE_RENDER;
    params.access_list = &tm.access;
    params.access_count = tm.access.len;
    params.pinned_thread = 0;
    params.user_data = tm;
    params.execute = system;
    var system_id: c.ke_system_id = 0;
    try R.check(rt.register_system.?(rt, &params, &system_id));
}

const testing = std.testing;

const Stubs = @import("stubs").Stubs(c);

fn testParams(rt: *Stubs.Runtime, core: *Stubs.Core, dev: *Stubs.Device) c.ke_render_tonemap_params {
    return .{ .runtime = rt.api(), .service = core.api(), .device = dev.api(), .frame_cid = 1 };
}

test "creating and destroying the tonemap pass leaves no block allocated and no GPU resource live" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var h: c.ke_render_tonemap_handle = undefined;
    try R.check(ke_render_tonemap_create(&testParams(&rt, &core, &dev), &h));
    h.destroy.?(h.ref);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try testing.expectEqual(@as(i64, 0), core.links);
    try heap.expectNoLeaks();
}

test "a tonemap pass whose shader fails to load releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    core.shader_loads_fail = true;
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var h: c.ke_render_tonemap_handle = undefined;
    try testing.expect(ke_render_tonemap_create(&testParams(&rt, &core, &dev), &h) != R.ok);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a tonemap pass the runtime refuses to register releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    rt.limit = 0;
    var h: c.ke_render_tonemap_handle = undefined;
    try testing.expect(ke_render_tonemap_create(&testParams(&rt, &core, &dev), &h) != R.ok);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a tonemap pass missing its device is refused as an invalid argument" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var p = testParams(&rt, &core, &dev);
    p.device = null;
    var h: c.ke_render_tonemap_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_tonemap_create(&p, &h)));
    try testing.expect(h.ref == null);
    try heap.expectNoLeaks();
}
