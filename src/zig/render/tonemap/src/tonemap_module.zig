//! The tonemap pass: the render-phase system "render.tonemap" that draws the "hdr" target into the
//! "backbuffer" target. It also owns the creation and teardown of that pass, behind the one
//! factory it exports.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };
const cimport = @import("cimport.zig");
const c = cimport.c;

const heap = @import("heap");
const gpa = heap.gpa;

const shader_group = c.ke_render_shader_group_params{
    .shader = "tonemap",
    .stages = c.KE_GPU_SHADER_STAGE_FRAGMENT,
    .block = null,
    .hints = null,
    .hint_count = 0,
};

/// The state of one tonemap pass. The factory allocates it and `destroyHandle` frees it. The
/// runtime receives it as the context of `system` at registration. `io` points into `reads` and
/// `writes` of this same struct, which stays valid because the module is never moved after
/// allocation.
pub const TonemapModule = struct {
    core: *c.ke_render_service = undefined,
    device: *c.ke_gpu_device = undefined,
    logger: ?*c.ke_logger = null,

    pipeline_params: c.ke_gpu_render_pipeline_params = undefined,
    group: c.ke_render_shader_group = .{ .layout = c.KE_GPU_INVALID_HANDLE, .index = 0 },
    bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,

    writes: [1][*c]const u8 = undefined,
    reads: [1][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
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
/// When the bind group cannot be created, the pass is ended, and the error output receives
/// `KE_ERROR_NOT_INITIALIZED` with the bind group error as its cause; the body then returns false.
/// Each frame it draws one full-screen triangle with no vertex input and no depth test, sampling
/// "hdr" through the shader named "tonemap". It recreates the bind group every frame, because the
/// "hdr" view is read from the pass each time.
fn system(_: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const tm = moduleOf(user);
    const core = tm.core;
    const dev = tm.device;

    const pc = core.*.begin_pass.?(core, &tm.io);
    if (pc == null) return true;

    const hdr_view = pc.*.read.?(pc, "hdr");
    const bindings = [1]c.ke_render_shader_binding{
        .{ .name = "t_hdr", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = hdr_view, .sampler = 0 },
    };
    if (tm.bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, tm.bind_group);
    var err: ?*c.ke_error = null;
    tm.bind_group = core.*.create_shader_bind_group.?(core, &shader_group, tm.group.layout, "tonemap.bind_group", &bindings, bindings.len, &err);
    if (tm.bind_group == c.KE_GPU_INVALID_HANDLE) {
        logGpuError(tm.logger, err, "tonemap bind group");
        core.*.end_pass.?(core, pc);
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "tonemap pass: bind group creation failed", @src().file, @intCast(@src().line), err);
        return false;
    }

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &tm.pipeline_params));
    rp.*.set_bind_group.?(rp, tm.group.index, tm.bind_group, null, 0);
    rp.*.draw.?(rp, 3, 1, 0, 0);
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
    return true;
}

/// Fills the module during `ke_render_tonemap_create`, before `system` is registered. A failed
/// shader load or layout request returns false before the layout exists; after it, a failed
/// pipeline request returns false with the layout left for the caller's release. The caller releases the module after any false return. A
/// successful call has asked the service for the pipeline once, so a failure surfaces at creation.
fn setup(tm: *TonemapModule, dev: *c.ke_gpu_device, core: *c.ke_render_service,
         logger: ?*c.ke_logger, out_error: [*c][*c]c.ke_error) bool {
    tm.core = core;
    tm.device = dev;
    tm.logger = logger;

    const vs = core.*.load_shader.?(core, "tonemap", c.KE_GPU_SHADER_STAGE_VERTEX, out_error);
    if (vs == c.KE_GPU_INVALID_HANDLE) return false;
    const fs = core.*.load_shader.?(core, "tonemap", c.KE_GPU_SHADER_STAGE_FRAGMENT, out_error);
    if (fs == c.KE_GPU_INVALID_HANDLE) return false;

    if (!core.*.shader_group_layout.?(core, &shader_group, &tm.group, out_error)) return false;
    var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    pp.label = "tonemap.pipeline";
    pp.vertex_module   = vs;
    pp.vertex_entry    = "vs_main";
    pp.fragment_module = fs;
    pp.fragment_entry  = "fs_main";
    pp.bind_group_layouts[tm.group.index] = tm.group.layout;
    pp.bind_group_layout_count = tm.group.index + 1;
    pp.color_target_formats[0] = core.*.backbuffer_format.?(core);
    pp.color_target_count = 1;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = 0;
    pp.depth_stencil.depth_write_enabled = 0;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
    tm.pipeline_params = pp;
    if (core.*.get_or_create_pipeline.?(core, &tm.pipeline_params) == c.KE_GPU_INVALID_HANDLE) return false;

    tm.bind_group = c.KE_GPU_INVALID_HANDLE;

    tm.writes = .{"backbuffer"};
    tm.reads  = .{"hdr"};
    tm.io = std.mem.zeroes(c.ke_render_pass_io);
    tm.io.name = "render.tonemap";
    tm.io.writes = @ptrCast(&tm.writes);
    tm.io.writes_count = 1;
    tm.io.reads = @ptrCast(&tm.reads);
    tm.io.reads_count = 1;
    tm.io.cmd_slot = 7;

    tm.access = .{
        .{ .cid = core.*.cid.?(core, "hdr"), .access = c.KE_ACCESS_READ },
        .{ .cid = core.*.cid.?(core, "backbuffer"), .access = c.KE_ACCESS_WRITE },
    };
    return true;
}

/// Releases the bind group of the last frame and the layout, each only when it is valid. Runs from
/// `destroyHandle` and from the failure paths of `ke_render_tonemap_create`.
fn destroyModule(tm: *const TonemapModule) void {
    const dev = tm.device;
    if (tm.bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, tm.bind_group);
    if (tm.group.layout != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group_layout.?(dev, tm.group.layout);
}

/// The `destroy` slot of the handle `ke_render_tonemap_create` returns. It releases the GPU objects
/// and frees the module; a null argument is ignored.
fn destroyHandle(self: ?*c.ke_render_tonemap) callconv(.c) void {
    const tm: *TonemapModule = @ptrCast(@alignCast(self orelse return));
    destroyModule(tm);
    gpa.destroy(tm);
}

/// The factory declared in tonemap_create.h. A null runtime, service or device returns a handle
/// with a null reference and leaves the error output untouched, as does a failed allocation. A
/// failed shader load in `setup`, or the runtime refusing `system`, sets the error output and
/// returns the null handle. On success the runtime holds the module as the context of `system`, and
/// the handle frees it.
export fn ke_render_tonemap_create(runtime: ?*c.ke_runtime, core: ?*c.ke_render_service,
                                    device: ?*c.ke_gpu_device, logger: ?*c.ke_logger,
                                    out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_tonemap_handle {
    const empty = c.ke_render_tonemap_handle{ .ref = null, .destroy = null };
    const rt = runtime orelse return empty;
    const core_ref = core orelse return empty;
    const dev = device orelse return empty;

    const tm = gpa.create(TonemapModule) catch return empty;
    tm.* = .{};
    if (!setup(tm, dev, core_ref, logger, out_error)) {
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

const testing = std.testing;

const Stubs = @import("stubs").Stubs(c);

test "creating and destroying the tonemap pass leaves no block allocated and no GPU resource live" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    const h = ke_render_tonemap_create(rt.api(), core.api(), dev.api(), null, null);
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
    try testing.expectEqual(@as(i64, 0), dev.live);
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
    const h = ke_render_tonemap_create(rt.api(), core.api(), dev.api(), null, null);
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
    const h = ke_render_tonemap_create(rt.api(), core.api(), dev.api(), null, null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}
