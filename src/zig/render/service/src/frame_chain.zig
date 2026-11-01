//! The frame's color and depth, and the chain of passes that work on the color in stage order:
//! which texture each link draws into and samples, the clear that opens the frame, and the draws
//! that carry the color through a link that recorded nothing and into the backbuffer.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_gpu = @import("abi_render_gpu");
const std = @import("std");
const rc = @import("render_service.zig");
const resource_table = @import("resource_table.zig");
const abi_ecs = @import("abi_ecs");
const abi_render = @import("abi_render");
const abi_result = @import("abi_result");
const R = rc.R;
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
    id: abi_asset_resolver.c.ke_render_chain_link,
    stage: abi_render.c.ke_render_stage,
    mode: abi_render.c.ke_render_chain_mode,
    source: abi_asset_resolver.c.ke_gpu_texture_view = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    target: abi_asset_resolver.c.ke_gpu_texture_view = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    target_format: abi_render_gpu.c.ke_gpu_texture_format = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_INVALID,
    recorded: std.atomic.Value(bool) = .init(false),

    /// True when the link's target starts as a copy of its source.
    pub fn startsAsSource(self: *const Link) bool {
        return self.source != abi_render_gpu.c.KE_GPU_INVALID_HANDLE and self.mode != abi_render.c.KE_RENDER_CHAIN_REPLACE;
    }
};

/// The links, kept sorted by stage and, within a stage, by the order they joined, so `links` is the
/// order the chain runs in. `colors` holds the indices into the service's resources of the two
/// textures of each format, `depth` the index of the frame's depth; `final` is the color the last
/// link leaves, which `endFrame` draws into the backbuffer. Links are added and removed only
/// outside a frame.
pub const Chain = struct {
    links: std.ArrayList(Link) = .empty,
    next_id: abi_asset_resolver.c.ke_render_chain_link = 1,
    color_format: abi_render_gpu.c.ke_gpu_texture_format = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_INVALID,
    colors: [2][2]usize = undefined,
    depth: usize = 0,
    final: abi_asset_resolver.c.ke_gpu_texture_view = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,

    pub fn deinit(self: *Chain) void {
        self.links.deinit(gpa);
    }

    /// The link of that id; null for an unknown one.
    pub fn find(self: *Chain, id: abi_asset_resolver.c.ke_render_chain_link) ?*Link {
        for (self.links.items) |*l| if (l.id == id) return l;
        return null;
    }
};

fn isLdr(stage: abi_render.c.ke_render_stage) usize {
    return if (stage >= abi_render.c.KE_RENDER_STAGE_TONEMAP) 1 else 0;
}

/// Declares the two color textures of each format, the frame's depth and the color tag, all the
/// size of the backbuffer. Called once by the factory, through the service's own `declare`.
pub fn prepare(st: *rc.CoreState, core: [*c]abi_render.c.ke_render_service, color_format: abi_render_gpu.c.ke_gpu_texture_format, depth_format: abi_render_gpu.c.ke_gpu_texture_format) R.Error!void {
    st.chain.color_format = color_format;
    const formats = [2]abi_render_gpu.c.ke_gpu_texture_format{ color_format, st.target.format.?(st.target) };
    for (color_names, formats, 0..) |pair, format, f| {
        for (pair, 0..) |name, i| {
            try declareTarget(core, name, format);
            st.chain.colors[f][i] = st.resources.items.len - 1;
        }
    }
    try declareTarget(core, abi_render.c.KE_RENDER_FRAME_DEPTH, depth_format);
    st.chain.depth = st.resources.items.len - 1;
    var color: abi_asset_resolver.c.ke_component_id = undefined;
    try R.check(resource_table.importTag(core, abi_render.c.KE_RENDER_FRAME_COLOR, &color));
}

fn declareTarget(core: [*c]abi_render.c.ke_render_service, name: [*:0]const u8, format: abi_render_gpu.c.ke_gpu_texture_format) R.Error!void {
    var cid: abi_asset_resolver.c.ke_component_id = undefined;
    try R.check(resource_table.declare(core, &abi_render.c.ke_render_resource_params{
        .name = name,
        .type = abi_render.c.KE_RENDER_RESOURCE_TEXTURE,
        .format = format,
        .size_mode = abi_render.c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0,
        .height = 0,
        .scale_x = 1.0,
        .scale_y = 1.0,
        .clear_value = .{ 0, 0, 0, 0 },
    }, &cid));
}

/// The service's `join_chain` slot. The new link goes after every link of a stage up to its own.
pub fn joinChain(self: [*c]abi_render.c.ke_render_service, stage: abi_render.c.ke_render_stage, mode: abi_render.c.ke_render_chain_mode, out_link: [*c]abi_asset_resolver.c.ke_render_chain_link) callconv(.c) abi_result.c.ke_result {
    const out = out_link orelse return R.code(error.InvalidArgument);
    out.* = abi_render.c.KE_RENDER_CHAIN_NONE;
    if (self == null) return R.code(error.InvalidArgument);
    if (stage < 0 or stage >= abi_render.c.KE_RENDER_STAGE_COUNT or mode < 0 or mode > abi_render.c.KE_RENDER_CHAIN_REPLACE) return R.code(error.InvalidArgument);
    const chain = &rc.coreOf(self).chain;
    var at: usize = 0;
    while (at < chain.links.items.len and chain.links.items[at].stage <= stage) at += 1;
    chain.links.insert(gpa, at, .{ .id = chain.next_id, .stage = stage, .mode = mode }) catch |err| return R.code(err);
    chain.next_id += 1;
    out.* = chain.links.items[at].id;
    return R.ok;
}

/// The service's `leave_chain` slot.
pub fn leaveChain(self: [*c]abi_render.c.ke_render_service, link: abi_asset_resolver.c.ke_render_chain_link) callconv(.c) void {
    if (self == null) return;
    const chain = &rc.coreOf(self).chain;
    for (chain.links.items, 0..) |l, i| {
        if (l.id != link) continue;
        _ = chain.links.orderedRemove(i);
        return;
    }
}

/// The service's `chain_format` slot.
pub fn chainFormat(self: [*c]abi_render.c.ke_render_service, stage: abi_render.c.ke_render_stage) callconv(.c) abi_render_gpu.c.ke_gpu_texture_format {
    if (self == null) return abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_INVALID;
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
        if (l.mode == abi_render.c.KE_RENDER_CHAIN_DRAW_OVER and want == f) {
            l.source = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
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
pub fn recordClear(st: *rc.CoreState) ?abi_render_gpu.c.ke_gpu_command_encoder_handle {
    var enc: abi_render_gpu.c.ke_gpu_command_encoder_handle = .{ .ref = null, .destroy = null };
    if (st.device.create_command_encoder.?(st.device, null, &enc) != R.ok) return null;
    const e = enc.ref orelse return null;
    const color = [1]abi_render_gpu.c.ke_gpu_color_attachment{.{
        .view = st.resources.items[st.chain.colors[0][0]].view,
        .load_op = abi_render_gpu.c.KE_GPU_LOAD_OP_CLEAR,
        .store_op = abi_render_gpu.c.KE_GPU_STORE_OP_STORE,
        .clear_value = .{ .color = st.clear_color },
    }};
    const depth = abi_render_gpu.c.ke_gpu_depth_stencil_attachment{
        .view = st.resources.items[st.chain.depth].view,
        .depth_load_op = abi_render_gpu.c.KE_GPU_LOAD_OP_CLEAR,
        .depth_store_op = abi_render_gpu.c.KE_GPU_STORE_OP_STORE,
        .stencil_store_op = abi_render_gpu.c.KE_GPU_STORE_OP_DONT_CARE,
        .clear_depth = 1.0,
        .clear_stencil = 0,
        .depth_read_only = false,
        .stencil_read_only = false,
    };
    const params = abi_render_gpu.c.ke_gpu_render_pass_params{
        .label = "render.frame.clear",
        .color_attachments = &color,
        .color_attachment_count = 1,
        .depth_stencil_attachment = &depth,
    };
    const rp = e.*.begin_render_pass.?(e, &params);
    rp.?.end.?(rp);
    return enc;
}

/// Records on a new encoder the draw of `src` over the whole of `dst`. Null when the device gives
/// no encoder or the draw cannot be recorded.
pub fn recordBlit(st: *rc.CoreState, src: abi_asset_resolver.c.ke_gpu_texture_view, dst: abi_asset_resolver.c.ke_gpu_texture_view, dst_format: abi_render_gpu.c.ke_gpu_texture_format) ?abi_render_gpu.c.ke_gpu_command_encoder_handle {
    var enc: abi_render_gpu.c.ke_gpu_command_encoder_handle = .{ .ref = null, .destroy = null };
    if (st.device.create_command_encoder.?(st.device, null, &enc) != R.ok) return null;
    const e = enc.ref orelse return null;
    if (!st.blit.draw(st.api, st.binder, e, src, dst, dst_format)) {
        enc.destroy.?(e);
        return null;
    }
    return enc;
}

/// The frame's depth view.
pub fn depthView(st: *rc.CoreState) abi_asset_resolver.c.ke_gpu_texture_view {
    return st.resources.items[st.chain.depth].view;
}
