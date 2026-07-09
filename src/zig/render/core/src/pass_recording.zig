const rc = @import("render_core.zig");
const c = rc.c;
const gpa = rc.gpa;

// Pass-recording surface: opens/closes a ke_render_pass_ctx, the render-pass
// begin (color/depth attachment resolution from named-resource writes), and
// the compute-pass recording proxy. wgpu-native cannot record a compute pass
// concurrently with a render pass (deadlock), so begin_compute hands back a
// proxy that appends commands into a per-slot ComputeRecord instead of a live
// device pass; end_frame (frame_lifecycle.zig) replays it single-threaded.

pub fn beginPass(self: [*c]c.ke_render_core, sys: ?*c.ke_system_ctx, io: [*c]const c.ke_render_pass_io) callconv(.c) [*c]c.ke_render_pass_ctx {
    _ = sys;
    const st = rc.coreOf(self);
    const ps = gpa.create(rc.PassState) catch return null;
    // Use this pass's pre-created encoder (made serially in begin_frame) so the
    // non-thread-safe create_command_encoder never runs on parallel pass threads.
    const slot = io.*.cmd_slot;
    const enc = if (slot < rc.NUM_PRECREATED_ENCODERS) st.cmd_encoders[slot] else st.device.create_command_encoder.?(st.device);
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

pub fn endPass(self: [*c]c.ke_render_core, ctx: [*c]c.ke_render_pass_ctx) callconv(.c) void {
    const st = rc.coreOf(self);
    const ps = rc.passOf(ctx);
    // Park the encoder in this pass's slot; end_frame finishes it single-threaded.
    // The encoder outlives this call (it is NOT destroyed here). Distinct slots →
    // no race with a parallel pass. A compute pass recorded nothing into the encoder
    // (its commands were accumulated in compute_records[slot]); cmd_valid stays false
    // so end_frame replays the compute record into this slot's encoder instead.
    const slot = ps.io.cmd_slot;
    if (slot < rc.MAX_CMD_BUFFERS) {
        st.cmd_encoders[slot] = ps.encoder;
        st.cmd_valid[slot] = !ps.is_compute;
    } else {
        ps.encoder.destroy.?(ps.encoder); // unreachable in practice; avoid a leak
    }
    gpa.destroy(ps);
    gpa.destroy(@as(*c.ke_render_pass_ctx, @ptrCast(ctx)));
}

fn ctxRead(self: [*c]c.ke_render_pass_ctx, name: [*c]const u8) callconv(.c) c.ke_gpu_texture_view {
    const ps = rc.passOf(self);
    if (ps.core.find(name)) |r| return r.view;
    return c.KE_GPU_INVALID_HANDLE;
}

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
            // io.load also governs depth: a pass that composites onto existing
            // color content (transparent-forward onto "hdr") tests against the
            // opaque depth someone else already wrote — it loads rather than
            // clears. depth_read_only stays false either way: that render-pass
            // flag is for sampling the SAME depth texture as a bound resource
            // while it's also attached (skybox's texel-fetch case), which this
            // pass doesn't do — the pipeline's depth_write_enabled=0 is what
            // actually prevents this pass from modifying the buffer it tests
            // against; the attachment's store_op is a harmless no-op write.
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
            // Use per-resource clear when alpha != 0 (explicit override); otherwise
            // fall back to the core's global scene clear color.
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
        .color_attachments = &colors,
        .color_attachment_count = color_count,
        .depth_stencil_attachment = if (has_depth) &depth else null,
    };
    return ps.encoder.begin_render_pass.?(ps.encoder, &params);
}

// Opens compute recording. Instead of a live device compute pass (recording one
// concurrently with a render pass deadlocks on wgpu-native), it hands back a proxy
// that appends the commands to this slot's compute_records; end_frame replays them
// single-threaded. The pass body uses the same ke_gpu_compute_pass interface.
fn ctxBeginCompute(self: [*c]c.ke_render_pass_ctx) callconv(.c) [*c]c.ke_gpu_compute_pass {
    const ps = rc.passOf(self);
    ps.is_compute = true;
    const slot = ps.io.cmd_slot;
    if (slot >= rc.MAX_CMD_BUFFERS) return null;
    const rec = &ps.core.compute_records[slot];
    rec.count = 0;
    rec.valid = true;
    rec.pass = .{
        .handle = rec,
        .device = ps.core.device,
        .set_pipeline = cpSetPipeline,
        .set_bind_group = cpSetBindGroup,
        .dispatch = cpDispatch,
        .dispatch_indirect = cpDispatchIndirect,
        .end = cpEnd,
    };
    return &rec.pass;
}

inline fn recOf(self: [*c]c.ke_gpu_compute_pass) *rc.ComputeRecord {
    return @alignCast(@ptrCast(self.*.handle));
}
fn cpAppend(rec: *rc.ComputeRecord, cmd: rc.ComputeCmd) void {
    if (rec.count >= rc.MAX_COMPUTE_CMDS) return; // overflow — raise MAX_COMPUTE_CMDS
    rec.cmds[rec.count] = cmd;
    rec.count += 1;
}
fn cpSetPipeline(self: [*c]c.ke_gpu_compute_pass, pipe: c.ke_gpu_pipeline) callconv(.c) void {
    cpAppend(recOf(self), .{ .set_pipeline = pipe });
}
fn cpSetBindGroup(self: [*c]c.ke_gpu_compute_pass, group_index: u32, bg: c.ke_gpu_bind_group,
                  dynamic_offsets: [*c]const u32, dyn_count: u32) callconv(.c) void {
    var off: [4]u32 = .{ 0, 0, 0, 0 };
    const n = @min(dyn_count, 4);
    var i: u32 = 0;
    while (i < n) : (i += 1) off[i] = dynamic_offsets[i];
    cpAppend(recOf(self), .{ .set_bind_group = .{ .index = group_index, .bg = bg, .offsets = off, .count = dyn_count } });
}
fn cpDispatch(self: [*c]c.ke_gpu_compute_pass, x: u32, y: u32, z: u32) callconv(.c) void {
    cpAppend(recOf(self), .{ .dispatch = .{ .x = x, .y = y, .z = z } });
}
fn cpDispatchIndirect(self: [*c]c.ke_gpu_compute_pass, indirect_buf: c.ke_gpu_buffer, offset: usize) callconv(.c) void {
    cpAppend(recOf(self), .{ .dispatch_indirect = .{ .buf = indirect_buf, .offset = offset } });
}
fn cpEnd(self: [*c]c.ke_gpu_compute_pass) callconv(.c) void {
    _ = self; // end is implicit — the replay in end_frame ends the real pass
}

fn ctxEncoder(self: [*c]c.ke_render_pass_ctx) callconv(.c) [*c]c.ke_gpu_command_encoder {
    return rc.passOf(self).encoder;
}

fn ctxQueryExt(self: [*c]c.ke_render_pass_ctx, name: [*c]const u8) callconv(.c) ?*const anyopaque {
    const ps = rc.passOf(self);
    return ps.core.device.query_extension.?(ps.core.device, name);
}

fn ctxBackbufferSize(self: [*c]c.ke_render_pass_ctx, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
    const ps = rc.passOf(self);
    if (out_w != null) out_w.* = ps.core.backbuffer_w;
    if (out_h != null) out_h.* = ps.core.backbuffer_h;
}
