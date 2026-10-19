//! The tonemap pass: the render-phase system "render.tonemap" that replaces the frame's HDR color
//! with its tonemapped copy, at the chain's tonemap stage. It also owns the creation and teardown
//! of that pass, behind the one factory it exports.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };
const c = @import("c");

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
    logger: ?*c.ke_logger = null,

    pipeline_params: c.ke_gpu_render_pipeline_params = undefined,
    binder: *c.ke_render_resource_binder = undefined,
    layout: c.ke_render_shader_layout = c.KE_RENDER_BINDING_INVALID,
    set: c.ke_render_resource_set = c.KE_RENDER_BINDING_INVALID,

    io: c.ke_render_pass_io = std.mem.zeroes(c.ke_render_pass_io),
    access: [2]c.ke_component_access = undefined,
};

/// Writes one error line to the logger, for a failure `system` has to report while it draws. Does
/// nothing when the logger or the error is absent, and drops a message that does not fit its
/// buffer.
fn logGpuError(logger: ?*c.ke_logger, err: ?*c.ke_error, what: []const u8) void {
    const lg = logger orelse return;
    const e = err orelse return;
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "{s} failed: {s}", .{ what, e.message }) catch return;
    var ev = c.ke_log_event{ .level = c.KE_LOG_LEVEL_ERROR, .tag = "render_tonemap", .message = msg.ptr };
    lg.log.?(lg, &ev);
}

inline fn moduleOf(user: ?*anyopaque) *TonemapModule {
    return @alignCast(@ptrCast(user.?));
}

/// The render-phase body that `ke_render_tonemap_create` registers, called by the runtime with the
/// module as its context. A frame in which the service begins no pass returns true without drawing.
/// When the set cannot be created, the pass is ended, and the error output receives
/// `KE_ERROR_NOT_INITIALIZED` with the set error as its cause; the body then returns false.
/// Each frame it draws one full-screen triangle with no vertex input and no depth test, sampling
/// the color source of its link through the shader named "tonemap". It recreates the set every
/// frame, because the source's view is read from the pass each time.
fn system(_: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const tm = moduleOf(user);
    const core = tm.core;

    const pc = core.*.begin_pass.?(core, &tm.io);
    if (pc == null) return true;

    const hdr_view = pc.*.color_source.?(pc);
    const bindings = [1]c.ke_render_shader_binding{
        .{ .name = "t_hdr", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = hdr_view, .sampler = 0 },
    };
    tm.binder.destroy_set.?(tm.binder, tm.set);
    var err: ?*c.ke_error = null;
    tm.set = tm.binder.create_set.?(tm.binder, tm.layout, null, "tonemap.set", &bindings, bindings.len, &err);
    if (tm.set == c.KE_RENDER_BINDING_INVALID) {
        logGpuError(tm.logger, err, "tonemap set");
        core.*.end_pass.?(core, pc);
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "tonemap pass: set creation failed", @src().file, @intCast(@src().line), err);
        return false;
    }

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &tm.pipeline_params));
    tm.binder.bind_render_set.?(tm.binder, rp, tm.set, null, 0);
    rp.*.draw.?(rp, 3, 1, 0, 0);
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
    return true;
}

/// Fills the module during `ke_render_tonemap_create`, before `system` is registered: joins the
/// chain and builds the pipeline in the format of the tonemap stage. A failed join, shader load or
/// layout request returns false before the layout exists; after it, a failed pipeline request
/// returns false with the layout left for the caller's release. The caller releases the module
/// after any false return. A successful call has asked the service for the pipeline once, so a
/// failure surfaces at creation.
/// Joining, it tells the runtime that the chain, not the runtime, orders the writers of the
/// frame's color.
fn setup(tm: *TonemapModule, p: *const c.ke_render_tonemap_params, out_error: [*c][*c]c.ke_error) bool {
    const core: *c.ke_render_service = p.service;
    tm.core = core;
    tm.device = p.device;
    tm.logger = p.logger;

    tm.io.name = "render.tonemap";
    tm.io.chain = core.*.join_chain.?(core, c.KE_RENDER_STAGE_TONEMAP, c.KE_RENDER_CHAIN_REPLACE, out_error);
    if (tm.io.chain == c.KE_RENDER_CHAIN_NONE) return false;
    if (!p.runtime.*.declare_self_ordered.?(p.runtime, core.*.cid.?(core, c.KE_RENDER_FRAME_COLOR), out_error)) return false;
    const format = core.*.chain_format.?(core, c.KE_RENDER_STAGE_TONEMAP);

    const vs = core.*.load_shader.?(core, "tonemap", c.KE_GPU_SHADER_STAGE_VERTEX, out_error);
    if (vs == c.KE_GPU_INVALID_HANDLE) return false;
    const fs = core.*.load_shader.?(core, "tonemap", c.KE_GPU_SHADER_STAGE_FRAGMENT, out_error);
    if (fs == c.KE_GPU_INVALID_HANDLE) return false;

    tm.binder = core.*.resource_binder.?(core);
    tm.layout = tm.binder.create_shader_layout.?(tm.binder, &shader_layout, out_error);
    if (tm.layout == c.KE_RENDER_BINDING_INVALID) return false;
    var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    pp.label = "tonemap.pipeline";
    pp.vertex_module   = vs;
    pp.vertex_entry    = "vs_main";
    pp.fragment_module = fs;
    pp.fragment_entry  = "fs_main";
    if (!tm.binder.pipeline_layouts.?(tm.binder, tm.layout, &pp.bind_group_layouts, pp.bind_group_layouts.len, &pp.bind_group_layout_count, out_error)) return false;
    pp.color_target_formats[0] = format;
    pp.color_target_count = 1;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = false;
    pp.depth_stencil.depth_write_enabled = false;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
    tm.pipeline_params = pp;
    if (core.*.get_or_create_pipeline.?(core, &tm.pipeline_params) == c.KE_GPU_INVALID_HANDLE) return false;

    tm.access = .{
        .{ .cid = core.*.cid.?(core, c.KE_RENDER_FRAME_COLOR), .access = c.KE_ACCESS_WRITE },
        .{ .cid = p.frame_cid, .access = c.KE_ACCESS_READ },
    };
    return true;
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
/// invalid argument and a failed allocation as out of memory. A failure in `setup`, or
/// the runtime refusing `system`, sets the error output and returns the null handle. On success the
/// runtime holds the module as the context of `system`, and the handle frees it.
export fn ke_render_tonemap_create(params_in: ?*const c.ke_render_tonemap_params,
                                    out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_tonemap_handle {
    const empty = c.ke_render_tonemap_handle{ .ref = null, .destroy = null };
    const p = params_in orelse return refused(out_error);
    const rt: *c.ke_runtime = p.runtime orelse return refused(out_error);
    if (p.service == null or p.device == null) return refused(out_error);

    const tm = gpa.create(TonemapModule) catch {
        c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "tonemap pass: allocation failed", @src().file, @intCast(@src().line), null);
        return empty;
    };
    tm.* = .{};
    if (!setup(tm, p, out_error)) {
        destroyModule(tm);
        gpa.destroy(tm);
        return empty;
    }

    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = "render.tonemap";
    params.phase = c.KE_PHASE_RENDER;
    params.access_list = &tm.access;
    params.access_count = tm.access.len;
    params.pinned_thread = 0;
    params.user_data = tm;
    params.execute = system;
    if (rt.register_system.?(rt, &params, out_error) == 0) {
        destroyModule(tm);
        gpa.destroy(tm);
        return empty;
    }

    return .{ .ref = @ptrCast(tm), .destroy = destroyHandle };
}

fn refused(out_error: [*c][*c]c.ke_error) c.ke_render_tonemap_handle {
    c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "tonemap pass: runtime, service and device are required", @src().file, @intCast(@src().line), null);
    return .{ .ref = null, .destroy = null };
}

const testing = std.testing;

const Stubs = @import("stubs").Stubs(c);

fn testParams(rt: *Stubs.Runtime, core: *Stubs.Core, dev: *Stubs.Device) c.ke_render_tonemap_params {
    return .{ .runtime = rt.api(), .service = core.api(), .device = dev.api(), .logger = null, .frame_cid = 1 };
}

test "creating and destroying the tonemap pass leaves no block allocated and no GPU resource live" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    const h = ke_render_tonemap_create(&testParams(&rt, &core, &dev), null);
    try testing.expect(h.ref != null);
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
    const h = ke_render_tonemap_create(&testParams(&rt, &core, &dev), null);
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
    const h = ke_render_tonemap_create(&testParams(&rt, &core, &dev), null);
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
    var err: [*c]c.ke_error = null;
    try testing.expect(ke_render_tonemap_create(&p, &err).ref == null);
    try testing.expectEqual(&c.KE_ERROR_INVALID_ARGUMENT, err.*.type);
    try heap.expectNoLeaks();
}
