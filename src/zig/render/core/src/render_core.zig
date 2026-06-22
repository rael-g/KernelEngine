const std = @import("std");

pub const c = @cImport({
    @cInclude("kernel_engine/ecs/ke_ecs.h");
    @cInclude("kernel_engine/render/gpu_device.h");
    @cInclude("kernel_engine/render/gpu_commands.h");
    @cInclude("kernel_engine/render/gpu_surface_ext.h");
    @cInclude("kernel_engine/render/core/render_core.h");
    @cInclude("kernel_engine/render/core/pass_context.h");
});

const gpa = std.heap.c_allocator;

const MAX_RESOURCES = 64;
const MAX_CMD_BUFFERS = 64;
const MAX_COLOR_ATTACH = 8;

const Resource = struct {
    name: [*c]const u8,
    cid: c.ke_component_id,
    format: c.ke_gpu_texture_format,
    texture: c.ke_gpu_texture,
    view: c.ke_gpu_texture_view,
    is_backbuffer: bool,
    is_transient: bool, // owns texture+view → destroyed on core destroy
};

const CoreState = struct {
    device: *c.ke_gpu_device,
    ecs: *c.ke_ecs,
    surface: ?*const c.ke_gpu_surface_ext,
    queue: c.ke_gpu_queue,

    resources: [MAX_RESOURCES]Resource,
    resource_count: u32,

    backbuffer_w: u32,
    backbuffer_h: u32,

    cmd_bufs: [MAX_CMD_BUFFERS][*c]c.ke_gpu_command_buffer,
    cmd_count: u32,

    fn find(self: *CoreState, name: [*c]const u8) ?*Resource {
        var i: u32 = 0;
        while (i < self.resource_count) : (i += 1) {
            if (std.mem.eql(u8, std.mem.span(self.resources[i].name), std.mem.span(name))) {
                return &self.resources[i];
            }
        }
        return null;
    }
};

const PassState = struct {
    core: *CoreState,
    io: c.ke_render_pass_io,
    encoder: *c.ke_gpu_command_encoder,
};

inline fn coreOf(self: [*c]c.ke_render_core) *CoreState {
    return @alignCast(@ptrCast(self.*.handle));
}
inline fn passOf(self: [*c]c.ke_render_pass_ctx) *PassState {
    return @alignCast(@ptrCast(self.*.handle));
}

fn isDepthFormat(fmt: c.ke_gpu_texture_format) bool {
    return fmt >= c.KE_GPU_TEXTURE_FORMAT_D16_UNORM and fmt <= c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT_S8_UINT;
}

// ── ke_render_core slots ────────────────────────────────────────────────────

fn declare(self: [*c]c.ke_render_core, desc: [*c]const c.ke_render_resource_desc, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
    _ = out_error;
    const st = coreOf(self);
    if (st.resource_count >= MAX_RESOURCES) return c.KE_COMPONENT_INVALID;

    const cid = st.ecs.component_register.?(st.ecs, desc.*.name, 0);

    var w = desc.*.width;
    var h = desc.*.height;
    if (desc.*.size_mode == c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER) {
        w = @intFromFloat(@as(f32, @floatFromInt(st.backbuffer_w)) * desc.*.scale_x);
        h = @intFromFloat(@as(f32, @floatFromInt(st.backbuffer_h)) * desc.*.scale_y);
    }

    const depth = isDepthFormat(desc.*.format);
    const usage: c.ke_gpu_texture_usage = if (depth)
        c.KE_GPU_TEXTURE_USAGE_DEPTH_ATTACH
    else
        c.KE_GPU_TEXTURE_USAGE_COLOR_ATTACH | c.KE_GPU_TEXTURE_USAGE_SAMPLED;

    const tex = st.device.create_texture.?(st.device, &c.ke_gpu_texture_params{
        .width = w,
        .height = h,
        .depth_or_array_layers = 1,
        .format = desc.*.format,
        .dimension = c.KE_GPU_TEXTURE_DIM_2D,
        .usage = usage,
        .mip_level_count = 1,
        .sample_count = 1,
        .initial_data = null,
        .initial_data_size = 0,
    });

    const view = st.device.create_texture_view.?(st.device, tex, &c.ke_gpu_texture_view_params{
        .format = desc.*.format,
        .dimension = c.KE_GPU_TEXTURE_DIM_2D,
        .aspect = if (depth) c.KE_GPU_TEXTURE_ASPECT_DEPTH else c.KE_GPU_TEXTURE_ASPECT_COLOR,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 1,
    });

    st.resources[st.resource_count] = .{
        .name = desc.*.name,
        .cid = cid,
        .format = desc.*.format,
        .texture = tex,
        .view = view,
        .is_backbuffer = false,
        .is_transient = true,
    };
    st.resource_count += 1;
    return cid;
}

fn importTexture(self: [*c]c.ke_render_core, name: [*c]const u8, tex: c.ke_gpu_texture, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
    _ = out_error;
    const st = coreOf(self);
    if (st.resource_count >= MAX_RESOURCES) return c.KE_COMPONENT_INVALID;
    const cid = st.ecs.component_register.?(st.ecs, name, 0);
    st.resources[st.resource_count] = .{
        .name = name,
        .cid = cid,
        .format = c.KE_GPU_TEXTURE_FORMAT_INVALID,
        .texture = tex,
        .view = c.KE_GPU_INVALID_HANDLE, // view creation needs a format — refinement
        .is_backbuffer = false,
        .is_transient = false,
    };
    st.resource_count += 1;
    return cid;
}

fn cidOf(self: [*c]c.ke_render_core, name: [*c]const u8) callconv(.c) c.ke_component_id {
    const st = coreOf(self);
    if (st.find(name)) |r| return r.cid;
    return c.KE_COMPONENT_INVALID;
}

fn beginPass(self: [*c]c.ke_render_core, sys: ?*c.ke_system_ctx, io: [*c]const c.ke_render_pass_io) callconv(.c) [*c]c.ke_render_pass_ctx {
    _ = sys;
    const st = coreOf(self);
    const ps = gpa.create(PassState) catch return null;
    ps.* = .{
        .core = st,
        .io = io.*,
        .encoder = st.device.create_command_encoder.?(st.device),
    };
    const ctx = gpa.create(c.ke_render_pass_ctx) catch {
        gpa.destroy(ps);
        return null;
    };
    ctx.* = .{
        .handle = ps,
        .read = ctxRead,
        .write = ctxRead,
        .begin_render = ctxBeginRender,
        .begin_compute = ctxBeginCompute,
        .encoder = ctxEncoder,
        .query_ext = ctxQueryExt,
        .backbuffer_size = ctxBackbufferSize,
    };
    return ctx;
}

fn endPass(self: [*c]c.ke_render_core, ctx: [*c]c.ke_render_pass_ctx) callconv(.c) void {
    const st = coreOf(self);
    const ps = passOf(ctx);
    const cmd = ps.encoder.finish.?(ps.encoder);
    ps.encoder.destroy.?(ps.encoder);
    if (st.cmd_count < MAX_CMD_BUFFERS) {
        st.cmd_bufs[st.cmd_count] = cmd;
        st.cmd_count += 1;
    }
    gpa.destroy(ps);
    gpa.destroy(@as(*c.ke_render_pass_ctx, @ptrCast(ctx)));
}

fn beginFrame(self: [*c]c.ke_render_core, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_bool {
    _ = out_error;
    const st = coreOf(self);
    st.cmd_count = 0;
    if (st.surface) |surf| {
        const view = surf.acquire_current_texture_view.?(surf);
        if (view == c.KE_GPU_INVALID_HANDLE) return 0;
        if (st.find("backbuffer")) |bb| bb.view = view;
    }
    return 1;
}

fn endFrame(self: [*c]c.ke_render_core, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_bool {
    _ = out_error;
    const st = coreOf(self);
    if (st.cmd_count > 0) {
        st.device.queue_submit.?(st.device, st.queue, &st.cmd_bufs, st.cmd_count);
        var i: u32 = 0;
        while (i < st.cmd_count) : (i += 1) {
            const cmd = st.cmd_bufs[i];
            cmd.*.destroy.?(cmd);
        }
        st.cmd_count = 0;
    }
    st.device.queue_present.?(st.device, st.queue);
    if (st.find("backbuffer")) |bb| {
        if (bb.view != c.KE_GPU_INVALID_HANDLE) {
            st.device.destroy_texture_view.?(st.device, bb.view);
            bb.view = c.KE_GPU_INVALID_HANDLE;
        }
    }
    return 1;
}

// ── ke_render_pass_ctx slots ────────────────────────────────────────────────

fn ctxRead(self: [*c]c.ke_render_pass_ctx, name: [*c]const u8) callconv(.c) c.ke_gpu_texture_view {
    const ps = passOf(self);
    if (ps.core.find(name)) |r| return r.view;
    return c.KE_GPU_INVALID_HANDLE;
}

fn ctxBeginRender(self: [*c]c.ke_render_pass_ctx) callconv(.c) [*c]c.ke_gpu_render_pass {
    const ps = passOf(self);
    var colors: [MAX_COLOR_ATTACH]c.ke_gpu_color_attachment = undefined;
    var color_count: u32 = 0;
    var depth: c.ke_gpu_depth_stencil_attachment = undefined;
    var has_depth = false;

    var i: u32 = 0;
    while (i < ps.io.writes_count) : (i += 1) {
        const r = ps.core.find(ps.io.writes[i]) orelse continue;
        if (isDepthFormat(r.format)) {
            depth = .{
                .view = r.view,
                .depth_load_op = c.KE_GPU_LOAD_OP_CLEAR,
                .depth_store_op = c.KE_GPU_STORE_OP_STORE,
                .stencil_store_op = c.KE_GPU_STORE_OP_DONT_CARE,
                .clear_depth = 1.0,
                .clear_stencil = 0,
                .depth_read_only = 0,
                .stencil_read_only = 0,
            };
            has_depth = true;
        } else if (color_count < MAX_COLOR_ATTACH) {
            colors[color_count] = .{
                .view = r.view,
                .load_op = c.KE_GPU_LOAD_OP_CLEAR,
                .store_op = c.KE_GPU_STORE_OP_STORE,
                .clear_value = .{ .color = .{ 0.0, 0.0, 0.0, 1.0 } },
            };
            color_count += 1;
        }
    }

    const params = c.ke_gpu_render_pass_params{
        .color_attachments = &colors,
        .color_attachment_count = color_count,
        .depth_stencil_attachment = if (has_depth) &depth else null,
    };
    return ps.encoder.begin_render_pass.?(ps.encoder, &params);
}

fn ctxBeginCompute(self: [*c]c.ke_render_pass_ctx) callconv(.c) [*c]c.ke_gpu_compute_pass {
    const ps = passOf(self);
    return ps.encoder.begin_compute_pass.?(ps.encoder);
}

fn ctxEncoder(self: [*c]c.ke_render_pass_ctx) callconv(.c) [*c]c.ke_gpu_command_encoder {
    return passOf(self).encoder;
}

fn ctxQueryExt(self: [*c]c.ke_render_pass_ctx, name: [*c]const u8) callconv(.c) ?*const anyopaque {
    const ps = passOf(self);
    return ps.core.device.query_extension.?(ps.core.device, name);
}

fn ctxBackbufferSize(self: [*c]c.ke_render_pass_ctx, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
    const ps = passOf(self);
    if (out_w != null) out_w.* = ps.core.backbuffer_w;
    if (out_h != null) out_h.* = ps.core.backbuffer_h;
}

// ── Factory + destroy ───────────────────────────────────────────────────────

fn destroyCore(self: [*c]c.ke_render_core) callconv(.c) void {
    const st = coreOf(self);
    var i: u32 = 0;
    while (i < st.resource_count) : (i += 1) {
        const r = &st.resources[i];
        if (r.is_transient) {
            if (r.view != c.KE_GPU_INVALID_HANDLE) st.device.destroy_texture_view.?(st.device, r.view);
            if (r.texture != c.KE_GPU_INVALID_HANDLE) st.device.destroy_texture.?(st.device, r.texture);
        }
    }
    gpa.destroy(st);
    gpa.destroy(@as(*c.ke_render_core, @ptrCast(self)));
}

export fn ke_render_core_create(device: ?*c.ke_gpu_device, ecs: ?*c.ke_ecs, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_core_handle {
    _ = out_error;
    const dev = device orelse return .{ .ref = null, .destroy = null };
    const e = ecs orelse return .{ .ref = null, .destroy = null };

    const st = gpa.create(CoreState) catch return .{ .ref = null, .destroy = null };
    const surf_raw = dev.query_extension.?(dev, c.KE_GPU_SURFACE_EXT_NAME);
    const surf: ?*const c.ke_gpu_surface_ext = if (surf_raw) |p| @ptrCast(@alignCast(p)) else null;
    st.* = .{
        .device = dev,
        .ecs = e,
        .surface = surf,
        .queue = dev.get_default_queue.?(dev),
        .resources = undefined,
        .resource_count = 0,
        .backbuffer_w = 0,
        .backbuffer_h = 0,
        .cmd_bufs = undefined,
        .cmd_count = 0,
    };

    // Built-in backbuffer resource (its view is refreshed each begin_frame).
    const bb_cid = e.component_register.?(e, "backbuffer", 0);
    st.resources[0] = .{
        .name = "backbuffer",
        .cid = bb_cid,
        .format = c.KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM,
        .texture = c.KE_GPU_INVALID_HANDLE,
        .view = c.KE_GPU_INVALID_HANDLE,
        .is_backbuffer = true,
        .is_transient = false,
    };
    st.resource_count = 1;

    const core = gpa.create(c.ke_render_core) catch {
        gpa.destroy(st);
        return .{ .ref = null, .destroy = null };
    };
    core.* = .{
        .handle = st,
        .declare = declare,
        .import_texture = importTexture,
        .cid = cidOf,
        .begin_pass = beginPass,
        .end_pass = endPass,
        .begin_frame = beginFrame,
        .end_frame = endFrame,
    };
    return .{ .ref = core, .destroy = destroyCore };
}
