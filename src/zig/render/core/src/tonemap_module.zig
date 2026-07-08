const std = @import("std");
const cimport = @import("cimport.zig");
const c = cimport.c;

// ACES tonemapping pass — reads the HDR buffer forward_module wrote and
// resolves it to the swapchain via the ACES fitted curve (Narkowicz 2015).
// A fullscreen-triangle pass with no vertex buffer; its only per-frame work is
// rebuilding the bind group against that frame's "hdr" texture view.

const tonemap_vs_wgsl = @embedFile("tonemap.vs.wgsl");
const tonemap_fs_wgsl = @embedFile("tonemap.fs.wgsl");

pub const TonemapModule = struct {
    core: c.ke_render_core_handle = undefined,
    device: *c.ke_gpu_device = undefined,
    logger: ?*c.ke_logger = null,

    pipeline: c.ke_gpu_pipeline = c.KE_GPU_INVALID_HANDLE,
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
    var ev = c.ke_log_event{ .level = c.KE_LOG_LEVEL_ERROR, .tag = "render_core", .message = msg.ptr };
    lg.log.?(lg, &ev);
}

inline fn moduleOf(user: ?*anyopaque) *TonemapModule {
    return @alignCast(@ptrCast(user.?));
}

pub fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const tm = moduleOf(user);
    const core = tm.core.ref;
    const dev = tm.device;

    const pc = core.*.begin_pass.?(core, ctx, &tm.io);
    if (pc == null) return;

    // Resolve the HDR texture view for this frame and rebuild the bind group.
    const hdr_view = pc.*.read.?(pc, "hdr");
    const samp = core.*.sampler.?(core);
    const entries = [2]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = hdr_view, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = samp },
    };
    // Destroy the previous frame's bind group before creating the new one.
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
    rp.*.set_pipeline.?(rp, tm.pipeline);
    rp.*.set_bind_group.?(rp, 0, tm.bind_group, null, 0);
    rp.*.draw.?(rp, 3, 1, 0, 0); // fullscreen triangle — no vertex buffer needed
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

pub fn setup(tm: *TonemapModule, dev: *c.ke_gpu_device, core: c.ke_render_core_handle,
             logger: ?*c.ke_logger, out_error: [*c][*c]c.ke_error) bool {
    tm.core = core;
    tm.device = dev;
    tm.logger = logger;

    const vs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{ .code = @ptrCast(tonemap_vs_wgsl), .byte_size = tonemap_vs_wgsl.len, .entry_point = "tonemap.vs" }, out_error);
    defer dev.destroy_shader_module.?(dev, vs);
    const fs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{ .code = @ptrCast(tonemap_fs_wgsl), .byte_size = tonemap_fs_wgsl.len, .entry_point = "tonemap.fs" }, out_error);
    defer dev.destroy_shader_module.?(dev, fs);

    // Set 0: { texture2D t_hdr @binding(0), sampler s_hdr @binding(1) }
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
    // no depth test — fullscreen triangle pass over backbuffer
    pp.depth_stencil.depth_test_enabled = 0;
    pp.depth_stencil.depth_write_enabled = 0;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
    tm.pipeline = dev.create_render_pipeline.?(dev, &pp);
    if (tm.pipeline == c.KE_GPU_INVALID_HANDLE) {
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
    tm.io.cmd_slot = 4; // after forward (slot 3)

    // "hdr" is declared by forward_module.setup (which runs first); resolve it
    // by name here rather than threading a cid across the module boundary.
    tm.access = .{
        .{ .cid = core.ref.*.cid.?(core.ref, "hdr"), .access = c.KE_ACCESS_READ },
        .{ .cid = core.ref.*.cid.?(core.ref, "backbuffer"), .access = c.KE_ACCESS_WRITE },
    };
    return true;
}

// Destroys the per-frame bind group + its layout — the only resources this
// module allocates that outlive a single setup call and need explicit teardown.
pub fn destroy(tm: *const TonemapModule) void {
    const dev = tm.device;
    if (tm.bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, tm.bind_group);
    if (tm.bgl != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group_layout.?(dev, tm.bgl);
}
