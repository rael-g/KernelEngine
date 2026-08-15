const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };
const cimport = @import("cimport.zig");
const c = cimport.c;

const gpa = std.heap.c_allocator;

pub const TonemapModule = struct {
    core: *c.ke_render_service = undefined,
    device: *c.ke_gpu_device = undefined,
    logger: ?*c.ke_logger = null,

    pipeline_params: c.ke_gpu_render_pipeline_params = undefined,
    bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE,
    bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,

    writes: [1][*c]const u8 = undefined,
    reads: [1][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
    access: [2]c.ke_component_access = undefined,
};

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

fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const tm = moduleOf(user);
    const core = tm.core;
    const dev = tm.device;

    const pc = core.*.begin_pass.?(core, ctx, &tm.io);
    if (pc == null) return;

    const hdr_view = pc.*.read.?(pc, "hdr");
    const samp = core.*.sampler.?(core);
    const entries = [2]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = hdr_view, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = samp },
    };
    if (tm.bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, tm.bind_group);
    var err: ?*c.ke_error = null;
    tm.bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = tm.bgl,
        .entry_count = 2,
        .entries = &entries,
    }, &err);
    if (err != null) logGpuError(tm.logger, err, "tonemap bind group");

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &tm.pipeline_params));
    rp.*.set_bind_group.?(rp, 0, tm.bind_group, null, 0);
    rp.*.draw.?(rp, 3, 1, 0, 0); // fullscreen triangle — no vertex buffer needed
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

fn setup(tm: *TonemapModule, dev: *c.ke_gpu_device, core: *c.ke_render_service,
         logger: ?*c.ke_logger, out_error: [*c][*c]c.ke_error) bool {
    tm.core = core;
    tm.device = dev;
    tm.logger = logger;

    const vs = core.*.load_shader.?(core, "tonemap", c.KE_GPU_SHADER_STAGE_VERTEX, out_error);
    if (vs == c.KE_GPU_INVALID_HANDLE) return false;
    const fs = core.*.load_shader.?(core, "tonemap", c.KE_GPU_SHADER_STAGE_FRAGMENT, out_error);
    if (fs == c.KE_GPU_INVALID_HANDLE) return false;

    const bgl_entries = [2]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = c.KE_GPU_TEXTURE_DIM_2D },
        .{ .binding = 1, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    const bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 2,
        .entries = &bgl_entries,
    });

    tm.bgl = bgl; // kept alive for per-frame bind group creation in system()
    var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    pp.vertex_module   = vs;
    pp.vertex_entry    = "vs_main";
    pp.fragment_module = fs;
    pp.fragment_entry  = "fs_main";
    pp.bind_group_layouts[0] = bgl;
    pp.bind_group_layout_count = 1;
    pp.color_target_formats[0] = 0; // swapchain surface format
    pp.color_target_count = 1;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = 0;
    pp.depth_stencil.depth_write_enabled = 0;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
    tm.pipeline_params = pp;
    if (core.*.get_or_create_pipeline.?(core, &tm.pipeline_params) == c.KE_GPU_INVALID_HANDLE) {
        dev.destroy_bind_group_layout.?(dev, bgl);
        return false;
    }

    tm.bind_group = c.KE_GPU_INVALID_HANDLE;

    tm.writes = .{"backbuffer"};
    tm.reads  = .{"hdr"};
    tm.io = std.mem.zeroes(c.ke_render_pass_io);
    tm.io.writes = @ptrCast(&tm.writes);
    tm.io.writes_count = 1;
    tm.io.reads = @ptrCast(&tm.reads);
    tm.io.reads_count = 1;
    tm.io.cmd_slot = 7; // after transparent-forward (slot 6)

    tm.access = .{
        .{ .cid = core.*.cid.?(core, "hdr"), .access = c.KE_ACCESS_READ },
        .{ .cid = core.*.cid.?(core, "backbuffer"), .access = c.KE_ACCESS_WRITE },
    };
    return true;
}

fn destroyModule(tm: *const TonemapModule) void {
    const dev = tm.device;
    if (tm.bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, tm.bind_group);
    if (tm.bgl != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group_layout.?(dev, tm.bgl);
}

fn destroyHandle(self: ?*c.ke_render_tonemap) callconv(.c) void {
    const tm: *TonemapModule = @ptrCast(@alignCast(self orelse return));
    destroyModule(tm);
    gpa.destroy(tm);
}

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
        gpa.destroy(tm);
        return empty;
    }

    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = "render.tonemap";
    params.phase = c.KE_PHASE_RENDER;
    params.access_list = &tm.access;
    params.access_count = tm.access.len;
    params.pinned_thread = 0; // render systems run in parallel (sim ‖ render + parallel passes)
    params.user_data = tm;
    params.execute = system;
    _ = rt.register_system.?(rt, &params, null);

    return .{ .ref = @ptrCast(tm), .destroy = destroyHandle };
}
