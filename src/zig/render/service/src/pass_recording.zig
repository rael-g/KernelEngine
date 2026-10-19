//! Hands out and takes back the pass contexts through which a pass draws or records compute work.

const rc = @import("render_service.zig");
const frame_chain = @import("frame_chain.zig");
const c = rc.c;
const gpa = rc.gpa;

/// Opens a pass on a command encoder of its own. The pass and its context stay allocated until
/// `endPass` frees them. Returns null, filling no error, when no frame is live, the device gives
/// no encoder or an allocation fails.
pub fn beginPass(self: [*c]c.ke_render_service, io: [*c]const c.ke_render_pass_io) callconv(.c) [*c]c.ke_render_pass_ctx {
    const st = rc.coreOf(self);
    if (!st.frame_live) return null;
    const enc = st.device.create_command_encoder.?(st.device, null, null);
    if (enc.ref == null) return null;
    const ps = gpa.create(rc.PassState) catch {
        enc.destroy.?(enc.ref);
        return null;
    };
    ps.* = .{
        .core = st,
        .io = io.*,
        .encoder = enc,
        .record = null,
    };
    const ctx = gpa.create(c.ke_render_pass_ctx) catch {
        enc.destroy.?(enc.ref);
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
        .color_source = ctxColorSource,
    };
    if (st.chain.find(io.*.chain)) |link| link.recorded.store(true, .monotonic);
    return ctx;
}

/// Places the pass's encoder next in the frame's submission order and frees the pass and its
/// context, so the context pointer is invalid afterwards. A pass that depends on another declares
/// access that conflicts with it, so the runtime runs it in a later wave and it ends later; passes
/// of one wave end in any order, which none of them depends on. A pass that finds no memory to
/// record its end is not submitted and its encoder is destroyed here.
pub fn endPass(self: [*c]c.ke_render_service, ctx: [*c]c.ke_render_pass_ctx) callconv(.c) void {
    const st = rc.coreOf(self);
    const ps = rc.passOf(ctx);
    if (st.ended.claim()) |slot| {
        slot.* = .{ .encoder = ps.encoder, .record = ps.record, .chain = ps.io.chain };
    } else {
        ps.encoder.destroy.?(ps.encoder.ref);
    }
    gpa.destroy(ps);
    gpa.destroy(@as(*c.ke_render_pass_ctx, @ptrCast(ctx)));
}

/// Returns the view of the named resource, or the invalid view for an unknown name. Also serves
/// the write slot of the context, so a write resolves its name the same way as a read.
fn ctxRead(self: [*c]c.ke_render_pass_ctx, name: [*c]const u8) callconv(.c) c.ke_gpu_texture_view {
    const ps = rc.passOf(self);
    if (ps.core.find(name)) |r| return r.view;
    return c.KE_GPU_INVALID_HANDLE;
}

/// A pass in the chain gets its link's target as its first color attachment: loaded, after the
/// link's source is drawn into it when the link starts from one, or cleared when the link
/// replaces the color. The writes follow, in the order of the pass's writes at the moment of this
/// call; its reads never become attachments. A write that names no resource is skipped, and so is
/// a color write past the attachment limit. Every write is cleared, a color write to its
/// resource's clear value when that value's alpha is not zero and to the service's clear color
/// otherwise. When no write is a depth resource and the pass asks for the frame's depth, that depth
/// is attached loaded and stored. The render pass it opens belongs to the caller, which ends it.
fn ctxBeginRender(self: [*c]c.ke_render_pass_ctx) callconv(.c) [*c]c.ke_gpu_render_pass {
    const ps = rc.passOf(self);
    var colors: [rc.MAX_COLOR_ATTACH]c.ke_gpu_color_attachment = undefined;
    var color_count: u32 = 0;
    var depth: c.ke_gpu_depth_stencil_attachment = undefined;
    var has_depth = false;
    const enc = ps.encoder.ref;

    if (ps.core.chain.find(ps.io.chain)) |link| {
        if (link.startsAsSource()) _ = ps.core.blit.draw(ps.core.api, ps.core.binder, enc, link.source, link.target, link.target_format);
        colors[0] = .{
            .view = link.target,
            .load_op = if (link.mode == c.KE_RENDER_CHAIN_REPLACE) c.KE_GPU_LOAD_OP_CLEAR else c.KE_GPU_LOAD_OP_LOAD,
            .store_op = c.KE_GPU_STORE_OP_STORE,
            .clear_value = .{ .color = ps.core.clear_color },
        };
        color_count = 1;
    }

    var i: u32 = 0;
    while (i < ps.io.writes_count) : (i += 1) {
        const r = ps.core.find(ps.io.writes[i]) orelse continue;
        if (rc.isDepthFormat(r.format)) {
            depth = .{
                .view = r.view,
                .depth_load_op = c.KE_GPU_LOAD_OP_CLEAR,
                .depth_store_op = c.KE_GPU_STORE_OP_STORE,
                .stencil_store_op = c.KE_GPU_STORE_OP_DONT_CARE,
                .clear_depth = 1.0,
                .clear_stencil = 0,
                .depth_read_only = false,
                .stencil_read_only = false,
            };
            has_depth = true;
        } else if (color_count < rc.MAX_COLOR_ATTACH) {
            const cv: [4]f32 = if (r.clear_value[3] != 0.0)
                r.clear_value
            else
                ps.core.clear_color;
            colors[color_count] = .{
                .view = r.view,
                .load_op = c.KE_GPU_LOAD_OP_CLEAR,
                .store_op = c.KE_GPU_STORE_OP_STORE,
                .clear_value = .{ .color = cv },
            };
            color_count += 1;
        }
    }

    if (!has_depth and ps.io.depth != c.KE_RENDER_DEPTH_NONE) {
        depth = .{
            .view = frame_chain.depthView(ps.core),
            .depth_load_op = c.KE_GPU_LOAD_OP_LOAD,
            .depth_store_op = c.KE_GPU_STORE_OP_STORE,
            .stencil_store_op = c.KE_GPU_STORE_OP_DONT_CARE,
            .clear_depth = 1.0,
            .clear_stencil = 0,
            .depth_read_only = false,
            .stencil_read_only = false,
        };
        has_depth = true;
    }

    const params = c.ke_gpu_render_pass_params{
        .label = ps.io.name,
        .color_attachments = &colors,
        .color_attachment_count = color_count,
        .depth_stencil_attachment = if (has_depth) &depth else null,
    };
    return enc.*.begin_render_pass.?(enc, &params);
}

/// The source of the pass's link when the link samples the color; the invalid view otherwise.
fn ctxColorSource(self: [*c]c.ke_render_pass_ctx) callconv(.c) c.ke_gpu_texture_view {
    const ps = rc.passOf(self);
    const link = ps.core.chain.find(ps.io.chain) orelse return c.KE_GPU_INVALID_HANDLE;
    if (link.mode == c.KE_RENDER_CHAIN_DRAW_OVER) return c.KE_GPU_INVALID_HANDLE;
    return link.source;
}

/// Takes the frame's next free record, empties it and returns a compute pass that records into it;
/// nothing runs until `endFrame` replays the record on the pass's encoder. Each call of the
/// returned pass appends a `ComputeCmd`. Null when no record can be allocated.
fn ctxBeginCompute(self: [*c]c.ke_render_pass_ctx) callconv(.c) [*c]c.ke_gpu_compute_pass {
    const ps = rc.passOf(self);
    const rec = ps.core.compute_records.claim() orelse return null;
    ps.record = rec;
    rec.cmds.clearRetainingCapacity();
    rec.offsets.clearRetainingCapacity();
    rec.pass_label = rec.storeLabel(ps.io.name);
    rec.pass = .{
        .handle = rec,
        .set_pipeline = cpSetPipeline,
        .set_bind_group = cpSetBindGroup,
        .dispatch = cpDispatch,
        .dispatch_indirect = cpDispatchIndirect,
        .end = cpEnd,
        .push_debug_group = cpPushDebugGroup,
        .pop_debug_group = cpPopDebugGroup,
        .insert_debug_marker = cpInsertDebugMarker,
    };
    return &rec.pass;
}

/// The record behind a compute pass handed out by `ctxBeginCompute`.
inline fn recOf(self: [*c]c.ke_gpu_compute_pass) *rc.ComputeRecord {
    return @alignCast(@ptrCast(self.*.handle));
}
/// Lost only when the record cannot grow, which the compute pass slots have no way to report.
fn cpAppend(rec: *rc.ComputeRecord, cmd: rc.ComputeCmd) void {
    rec.cmds.append(rc.gpa, cmd) catch {};
}
/// Records the command.
fn cpSetPipeline(self: [*c]c.ke_gpu_compute_pass, pipe: c.ke_gpu_pipeline) callconv(.c) void {
    cpAppend(recOf(self), .{ .set_pipeline = pipe });
}
/// Copies the dynamic offsets into the command at record time, so the caller's array need not
/// outlive the call.
fn cpSetBindGroup(self: [*c]c.ke_gpu_compute_pass, group_index: u32, bg: c.ke_gpu_bind_group,
                  dynamic_offsets: [*c]const u32, dyn_count: u32) callconv(.c) void {
    const rec = recOf(self);
    const first: u32 = @intCast(rec.offsets.items.len);
    if (dyn_count > 0) rec.offsets.appendSlice(rc.gpa, dynamic_offsets[0..dyn_count]) catch return;
    cpAppend(rec, .{ .set_bind_group = .{ .index = group_index, .bg = bg, .first_offset = first, .count = dyn_count } });
}
/// Records the command; dropped when the record is full.
fn cpDispatch(self: [*c]c.ke_gpu_compute_pass, x: u32, y: u32, z: u32) callconv(.c) void {
    cpAppend(recOf(self), .{ .dispatch = .{ .x = x, .y = y, .z = z } });
}
/// Records the command; dropped when the record is full.
fn cpDispatchIndirect(self: [*c]c.ke_gpu_compute_pass, indirect_buf: c.ke_gpu_buffer, offset: usize) callconv(.c) void {
    cpAppend(recOf(self), .{ .dispatch_indirect = .{ .buf = indirect_buf, .offset = offset } });
}
/// Has no effect: the commands are already in the record, and the frame replays them.
fn cpEnd(self: [*c]c.ke_gpu_compute_pass) callconv(.c) void {
    _ = self;
}
/// Records the group with a copy of the label; dropped when the record is full.
fn cpPushDebugGroup(self: [*c]c.ke_gpu_compute_pass, label: [*c]const u8) callconv(.c) void {
    const rec = recOf(self);
    cpAppend(rec, .{ .push_debug_group = rec.storeLabel(label) });
}
/// Records the command; dropped when the record is full.
fn cpPopDebugGroup(self: [*c]c.ke_gpu_compute_pass) callconv(.c) void {
    cpAppend(recOf(self), .pop_debug_group);
}
/// Records the marker with a copy of the label; dropped when the record is full.
fn cpInsertDebugMarker(self: [*c]c.ke_gpu_compute_pass, label: [*c]const u8) callconv(.c) void {
    const rec = recOf(self);
    cpAppend(rec, .{ .insert_debug_marker = rec.storeLabel(label) });
}

/// Returns the pass's raw command encoder; the pass keeps recording into the same one.
fn ctxEncoder(self: [*c]c.ke_render_pass_ctx) callconv(.c) [*c]c.ke_gpu_command_encoder {
    return rc.passOf(self).encoder.ref;
}

/// Forwards to the device's `query_extension`; null when the device has no such extension.
fn ctxQueryExt(self: [*c]c.ke_render_pass_ctx, name: [*c]const u8) callconv(.c) ?*const anyopaque {
    const ps = rc.passOf(self);
    return ps.core.device.query_extension.?(ps.core.device, name);
}

/// Reports the backbuffer size read at the last `beginFrame`.
fn ctxBackbufferSize(self: [*c]c.ke_render_pass_ctx, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
    const ps = rc.passOf(self);
    if (out_w != null) out_w.* = ps.core.backbuffer_w;
    if (out_h != null) out_h.* = ps.core.backbuffer_h;
}
