//! The frame's color and depth, and the chain of passes that work on the color in stage order:
//! which texture each link draws into and samples, the clear that opens the frame, and the draws
//! that carry the color through a link that recorded nothing and into the backbuffer.

const std = @import("std");
const rc = @import("render_service.zig");
const resource_table = @import("resource_table.zig");
const c = rc.c;
const gpa = rc.gpa;

const color_names = [2][2][*:0]const u8{
    .{ "frame.color.hdr.0", "frame.color.hdr.1" },
    .{ "frame.color.ldr.0", "frame.color.ldr.1" },
};

/// One place in the chain. `source`, `target` and `target_format` are set by `assign` when a frame
/// begins and read by the passes of that frame; `source` is the invalid view when the link draws
/// over the current color in the format it already has. `recorded` is set when the link's pass
/// begins, from whichever worker runs it.
pub const Link = struct {
    id: c.ke_render_chain_link,
    stage: c.ke_render_stage,
    mode: c.ke_render_chain_mode,
    source: c.ke_gpu_texture_view = c.KE_GPU_INVALID_HANDLE,
    target: c.ke_gpu_texture_view = c.KE_GPU_INVALID_HANDLE,
    target_format: c.ke_gpu_texture_format = c.KE_GPU_TEXTURE_FORMAT_INVALID,
    recorded: std.atomic.Value(bool) = .init(false),

    /// True when the link's target starts as a copy of its source.
    pub fn startsAsSource(self: *const Link) bool {
        return self.source != c.KE_GPU_INVALID_HANDLE and self.mode != c.KE_RENDER_CHAIN_REPLACE;
    }
};

/// The links, kept sorted by stage and, within a stage, by the order they joined, so `links` is the
/// order the chain runs in. `colors` holds the indices into the service's resources of the two
/// textures of each format, `depth` the index of the frame's depth; `final` is the color the last
/// link leaves, which `endFrame` draws into the backbuffer. Links are added and removed only
/// outside a frame.
pub const Chain = struct {
    links: std.ArrayList(Link) = .empty,
    next_id: c.ke_render_chain_link = 1,
    color_format: c.ke_gpu_texture_format = c.KE_GPU_TEXTURE_FORMAT_INVALID,
    colors: [2][2]usize = undefined,
    depth: usize = 0,
    final: c.ke_gpu_texture_view = c.KE_GPU_INVALID_HANDLE,

    pub fn deinit(self: *Chain) void {
        self.links.deinit(gpa);
    }

    /// The link of that id; null for an unknown one.
    pub fn find(self: *Chain, id: c.ke_render_chain_link) ?*Link {
        for (self.links.items) |*l| if (l.id == id) return l;
        return null;
    }
};

fn isLdr(stage: c.ke_render_stage) usize {
    return if (stage >= c.KE_RENDER_STAGE_TONEMAP) 1 else 0;
}

/// Declares the two color textures of each format, the frame's depth and the color tag, all the
/// size of the backbuffer. Called once by the factory, through the service's own `declare`.
/// Returns false with the error set when a declaration fails.
pub fn prepare(st: *rc.CoreState, core: [*c]c.ke_render_service, color_format: c.ke_gpu_texture_format, depth_format: c.ke_gpu_texture_format, out_error: [*c][*c]c.ke_error) bool {
    st.chain.color_format = color_format;
    const formats = [2]c.ke_gpu_texture_format{ color_format, st.target.format.?(st.target) };
    for (color_names, formats, 0..) |pair, format, f| {
        for (pair, 0..) |name, i| {
            if (!declareTarget(core, name, format, out_error)) return false;
            st.chain.colors[f][i] = st.resources.items.len - 1;
        }
    }
    if (!declareTarget(core, c.KE_RENDER_FRAME_DEPTH, depth_format, out_error)) return false;
    st.chain.depth = st.resources.items.len - 1;
    return resource_table.importTag(core, c.KE_RENDER_FRAME_COLOR, out_error) != c.KE_COMPONENT_INVALID;
}

fn declareTarget(core: [*c]c.ke_render_service, name: [*:0]const u8, format: c.ke_gpu_texture_format, out_error: [*c][*c]c.ke_error) bool {
    return resource_table.declare(core, &c.ke_render_resource_params{
        .name = name,
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = format,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0,
        .height = 0,
        .scale_x = 1.0,
        .scale_y = 1.0,
        .clear_value = .{ 0, 0, 0, 0 },
    }, out_error) != c.KE_COMPONENT_INVALID;
}

/// The service's `join_chain` slot. The new link goes after every link of a stage up to its own.
pub fn joinChain(self: [*c]c.ke_render_service, stage: c.ke_render_stage, mode: c.ke_render_chain_mode, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_chain_link {
    if (self == null) {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "join_chain: service is required", @src().file, @intCast(@src().line), null);
        return c.KE_RENDER_CHAIN_NONE;
    }
    if (stage < 0 or stage >= c.KE_RENDER_STAGE_COUNT or mode < 0 or mode > c.KE_RENDER_CHAIN_REPLACE) {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "join_chain: stage or mode out of range", @src().file, @intCast(@src().line), null);
        return c.KE_RENDER_CHAIN_NONE;
    }
    const chain = &rc.coreOf(self).chain;
    var at: usize = 0;
    while (at < chain.links.items.len and chain.links.items[at].stage <= stage) at += 1;
    chain.links.insert(gpa, at, .{ .id = chain.next_id, .stage = stage, .mode = mode }) catch {
        c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "join_chain: link allocation failed", @src().file, @intCast(@src().line), null);
        return c.KE_RENDER_CHAIN_NONE;
    };
    chain.next_id += 1;
    return chain.links.items[at].id;
}

/// The service's `leave_chain` slot.
pub fn leaveChain(self: [*c]c.ke_render_service, link: c.ke_render_chain_link) callconv(.c) void {
    if (self == null) return;
    const chain = &rc.coreOf(self).chain;
    for (chain.links.items, 0..) |l, i| {
        if (l.id != link) continue;
        _ = chain.links.orderedRemove(i);
        return;
    }
}

/// The service's `chain_format` slot.
pub fn chainFormat(self: [*c]c.ke_render_service, stage: c.ke_render_stage) callconv(.c) c.ke_gpu_texture_format {
    if (self == null) return c.KE_GPU_TEXTURE_FORMAT_INVALID;
    const st = rc.coreOf(self);
    return st.resources.items[st.chain.colors[isLdr(stage)][0]].format;
}

/// Walks the links in order from the first color texture, which the frame's clear fills. A link
/// that draws over a color of its own format draws into it; any other link gets the other texture
/// of its format as target and the current color as source, and its target becomes the current
/// color. Called by `beginFrame` once the resources have their size for the frame.
pub fn assign(st: *rc.CoreState) void {
    var f: usize = 0;
    var i: usize = 0;
    for (st.chain.links.items) |*l| {
        l.recorded.store(false, .monotonic);
        const want = isLdr(l.stage);
        if (l.mode == c.KE_RENDER_CHAIN_DRAW_OVER and want == f) {
            l.source = c.KE_GPU_INVALID_HANDLE;
        } else {
            l.source = st.resources.items[st.chain.colors[f][i]].view;
            i = if (want == f) 1 - i else 0;
            f = want;
        }
        const r = &st.resources.items[st.chain.colors[f][i]];
        l.target = r.view;
        l.target_format = r.format;
    }
    st.chain.final = st.resources.items[st.chain.colors[f][i]].view;
}

/// Records on a new encoder the clear of the first color texture to the service's clear color and
/// of the frame's depth to the far plane. Null when the device gives no encoder.
pub fn recordClear(st: *rc.CoreState) ?c.ke_gpu_command_encoder_handle {
    const enc = st.device.create_command_encoder.?(st.device, null, null);
    const e = enc.ref orelse return null;
    const color = [1]c.ke_gpu_color_attachment{.{
        .view = st.resources.items[st.chain.colors[0][0]].view,
        .load_op = c.KE_GPU_LOAD_OP_CLEAR,
        .store_op = c.KE_GPU_STORE_OP_STORE,
        .clear_value = .{ .color = st.clear_color },
    }};
    const depth = c.ke_gpu_depth_stencil_attachment{
        .view = st.resources.items[st.chain.depth].view,
        .depth_load_op = c.KE_GPU_LOAD_OP_CLEAR,
        .depth_store_op = c.KE_GPU_STORE_OP_STORE,
        .stencil_store_op = c.KE_GPU_STORE_OP_DONT_CARE,
        .clear_depth = 1.0,
        .clear_stencil = 0,
        .depth_read_only = false,
        .stencil_read_only = false,
    };
    const params = c.ke_gpu_render_pass_params{
        .label = "render.frame.clear",
        .color_attachments = &color,
        .color_attachment_count = 1,
        .depth_stencil_attachment = &depth,
    };
    const rp = e.*.begin_render_pass.?(e, &params);
    rp.*.end.?(rp);
    return enc;
}

/// Records on a new encoder the draw of `src` over the whole of `dst`. Null when the device gives
/// no encoder or the draw cannot be recorded.
pub fn recordBlit(st: *rc.CoreState, src: c.ke_gpu_texture_view, dst: c.ke_gpu_texture_view, dst_format: c.ke_gpu_texture_format) ?c.ke_gpu_command_encoder_handle {
    const enc = st.device.create_command_encoder.?(st.device, null, null);
    const e = enc.ref orelse return null;
    if (!st.blit.draw(st.api, st.binder, e, src, dst, dst_format)) {
        enc.destroy.?(e);
        return null;
    }
    return enc;
}

/// The frame's depth view.
pub fn depthView(st: *rc.CoreState) c.ke_gpu_texture_view {
    return st.resources.items[st.chain.depth].view;
}
