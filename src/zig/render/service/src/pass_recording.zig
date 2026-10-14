//! Hands out and takes back the pass contexts through which a pass draws or records compute work.

const rc = @import("render_service.zig");
const c = rc.c;
const gpa = rc.gpa;

/// Opens a pass in the command slot of the io. The encoder is the slot's precreated one, or a
/// fresh one for a slot past the precreated ones. The pass and its context stay allocated until
/// `endPass` frees them. Returns null, filling no error, when no frame is live or an allocation
/// fails.
pub fn beginPass(self: [*c]c.ke_render_service, io: [*c]const c.ke_render_pass_io) callconv(.c) [*c]c.ke_render_pass_ctx {
    const st = rc.coreOf(self);
    if (!st.frame_live) return null;
    const ps = gpa.create(rc.PassState) catch return null;
    const slot = io.*.cmd_slot;
    const enc = if (slot < rc.NUM_PRECREATED_ENCODERS) st.cmd_encoders[slot] else st.device.create_command_encoder.?(st.device, null);
    ps.* = .{
        .core = st,
        .io = io.*,
        .encoder = enc,
        .is_compute = false,
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

/// Hands the encoder back to its slot and frees the pass and its context, so the context pointer is
/// invalid afterwards. The slot is flagged for submission unless the pass was compute, so a slot is
/// either finished as a render encoder or replayed from its compute record. A slot past the
/// command-buffer limit has no entry in the slot arrays, so its encoder is destroyed here instead.
pub fn endPass(self: [*c]c.ke_render_service, ctx: [*c]c.ke_render_pass_ctx) callconv(.c) void {
    const st = rc.coreOf(self);
    const ps = rc.passOf(ctx);
    const slot = ps.io.cmd_slot;
    if (slot < rc.MAX_CMD_BUFFERS) {
        st.cmd_encoders[slot] = ps.encoder;
        st.cmd_valid[slot] = !ps.is_compute;
    } else {
        ps.encoder.destroy.?(ps.encoder);
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

/// Attachments follow the order of the pass's writes at the moment of this call; its reads never
/// become attachments. A write that names no resource is skipped, and so is a color write past
/// the attachment limit. A depth write is cleared, or loaded when the pass asks to load. A color
/// write takes its resource's clear value when that value's alpha is not zero, and the service's
/// clear color otherwise. The render pass it opens belongs to the caller, which ends it.
fn ctxBeginRender(self: [*c]c.ke_render_pass_ctx) callconv(.c) [*c]c.ke_gpu_render_pass {
    const ps = rc.passOf(self);
    var colors: [rc.MAX_COLOR_ATTACH]c.ke_gpu_color_attachment = undefined;
    var color_count: u32 = 0;
    var depth: c.ke_gpu_depth_stencil_attachment = undefined;
    var has_depth = false;

    var i: u32 = 0;
    while (i < ps.io.writes_count) : (i += 1) {
        const r = ps.core.find(ps.io.writes[i]) orelse continue;
        if (rc.isDepthFormat(r.format)) {
            depth = if (ps.io.load != 0) .{
                .view = r.view,
                .depth_load_op = c.KE_GPU_LOAD_OP_LOAD,
                .depth_store_op = c.KE_GPU_STORE_OP_STORE,
                .stencil_store_op = c.KE_GPU_STORE_OP_DONT_CARE,
                .clear_depth = 1.0,
                .clear_stencil = 0,
                .depth_read_only = 0,
                .stencil_read_only = 0,
            } else .{
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
        } else if (color_count < rc.MAX_COLOR_ATTACH) {
            const cv: [4]f32 = if (r.clear_value[3] != 0.0)
                r.clear_value
            else
                ps.core.clear_color;
            colors[color_count] = .{
                .view = r.view,
                .load_op = if (ps.io.load != 0) c.KE_GPU_LOAD_OP_LOAD else c.KE_GPU_LOAD_OP_CLEAR,
                .store_op = c.KE_GPU_STORE_OP_STORE,
                .clear_value = .{ .color = cv },
            };
            color_count += 1;
        }
    }

    const params = c.ke_gpu_render_pass_params{
        .label = ps.io.name,
        .color_attachments = &colors,
        .color_attachment_count = color_count,
        .depth_stencil_attachment = if (has_depth) &depth else null,
    };
    return ps.encoder.begin_render_pass.?(ps.encoder, &params);
}

/// Replaces the slot's record with an empty one and returns a compute pass that records into it;
/// nothing runs until `endFrame` replays the record on the slot's encoder. Each call of the
/// returned pass appends a `ComputeCmd`. A slot past the command-buffer limit gets null.
fn ctxBeginCompute(self: [*c]c.ke_render_pass_ctx) callconv(.c) [*c]c.ke_gpu_compute_pass {
    const ps = rc.passOf(self);
    ps.is_compute = true;
    const slot = ps.io.cmd_slot;
    if (slot >= rc.MAX_CMD_BUFFERS) return null;
    const rec = &ps.core.compute_records[slot];
    rec.count = 0;
    rec.valid = true;
    rec.pass_label = rec.storeLabel(ps.io.name);
    rec.pass = .{
        .handle = rec,
        .device = ps.core.device,
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
fn cpAppend(rec: *rc.ComputeRecord, cmd: rc.ComputeCmd) void {
    if (rec.count >= rc.MAX_COMPUTE_CMDS) return;
    rec.cmds[rec.count] = cmd;
    rec.count += 1;
}
/// Records the command; dropped when the record is full.
fn cpSetPipeline(self: [*c]c.ke_gpu_compute_pass, pipe: c.ke_gpu_pipeline) callconv(.c) void {
    cpAppend(recOf(self), .{ .set_pipeline = pipe });
}
/// Copies the dynamic offsets into the command at record time, so the caller's array need not
/// outlive the call.
fn cpSetBindGroup(self: [*c]c.ke_gpu_compute_pass, group_index: u32, bg: c.ke_gpu_bind_group,
                  dynamic_offsets: [*c]const u32, dyn_count: u32) callconv(.c) void {
    var off: [4]u32 = .{ 0, 0, 0, 0 };
    const n = @min(dyn_count, 4);
    var i: u32 = 0;
    while (i < n) : (i += 1) off[i] = dynamic_offsets[i];
    cpAppend(recOf(self), .{ .set_bind_group = .{ .index = group_index, .bg = bg, .offsets = off, .count = dyn_count } });
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

/// Returns the slot's raw command encoder; the pass keeps recording into the same one.
fn ctxEncoder(self: [*c]c.ke_render_pass_ctx) callconv(.c) [*c]c.ke_gpu_command_encoder {
    return rc.passOf(self).encoder;
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
