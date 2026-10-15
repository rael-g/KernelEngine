//! Opens and closes a frame of the render service, and carries the buffer uploads queued during it.

const rc = @import("render_service.zig");
const resource_table = @import("resource_table.zig");
const c = rc.c;

/// Opens a frame. The previous frame's slot flags, compute records and upload counters are
/// cleared before the target is acquired, so a failed acquire leaves the frame closed and
/// returns zero with the target's error. Once it has returned one, the precreated encoders
/// exist, the backbuffer size is read from the target, the "backbuffer" entry holds the acquired
/// view and the frame is live.
pub fn beginFrame(self: [*c]c.ke_render_service, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_bool {
    const st = rc.coreOf(self);
    st.frame_live = false;
    @memset(st.cmd_valid[0..], false);
    for (&st.compute_records) |*r| {
        r.valid = false;
        r.count = 0;
        r.labels.clearRetainingCapacity();
    }
    st.upload_count.store(0, .monotonic);
    st.upload_arena_offset.store(0, .monotonic);
    const view = st.target.acquire.?(st.target, out_error);
    if (view == c.KE_GPU_INVALID_HANDLE) return 0;
    var pe: u32 = 0;
    while (pe < rc.NUM_PRECREATED_ENCODERS) : (pe += 1) {
        st.cmd_encoders[pe] = st.device.create_command_encoder.?(st.device, null);
    }
    st.target.size.?(st.target, &st.backbuffer_w, &st.backbuffer_h);
    resource_table.resizeRelative(st);
    if (st.find("backbuffer")) |bb| bb.view = view;
    st.frame_live = true;
    return 1;
}

/// Closes the frame. The queued uploads are written to their buffers before any command buffer
/// is finished. Each slot flagged by `endPass` has its encoder finished, and a slot that holds
/// only a compute record has the record replayed on its encoder first. The command buffers are
/// submitted in one call and destroyed, the precreated encoders are destroyed, and the frame
/// stops being live. Returns the result of the present, with the target's error on failure; the
/// queue is polled whatever it returned. Returns zero and does nothing when no frame is live.
pub fn endFrame(self: [*c]c.ke_render_service, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_bool {
    const st = rc.coreOf(self);
    if (!st.frame_live) return 0;

    const ucount = @min(st.upload_count.load(.monotonic), rc.MAX_UPLOADS);
    var u: u32 = 0;
    while (u < ucount) : (u += 1) {
        const r = st.upload_records[u];
        st.device.write_buffer.?(st.device, r.buffer, r.gpu_offset, &st.upload_arena[r.arena_offset], r.size);
    }

    var submit: [rc.MAX_CMD_BUFFERS][*c]c.ke_gpu_command_buffer = undefined;
    var n: u32 = 0;
    var s: u32 = 0;
    while (s < rc.MAX_CMD_BUFFERS) : (s += 1) {
        if (st.cmd_valid[s]) {
            const enc = st.cmd_encoders[s];
            submit[n] = enc.*.finish.?(enc);
            n += 1;
        } else if (st.compute_records[s].valid) {
            const enc = st.cmd_encoders[s];
            const rec = &st.compute_records[s];
            const cp = enc.*.begin_compute_pass.?(enc, &c.ke_gpu_compute_pass_params{ .label = rec.label(rec.pass_label) });
            var ci: u32 = 0;
            while (ci < rec.count) : (ci += 1) {
                switch (rec.cmds[ci]) {
                    .set_pipeline => |p| cp.*.set_pipeline.?(cp, p),
                    .set_bind_group => |b| {
                        if (b.count > 0)
                            cp.*.set_bind_group.?(cp, b.index, b.bg, &b.offsets, b.count)
                        else
                            cp.*.set_bind_group.?(cp, b.index, b.bg, null, 0);
                    },
                    .dispatch => |d| cp.*.dispatch.?(cp, d.x, d.y, d.z),
                    .dispatch_indirect => |d| cp.*.dispatch_indirect.?(cp, d.buf, d.offset),
                    .push_debug_group => |l| cp.*.push_debug_group.?(cp, rec.label(l)),
                    .pop_debug_group => cp.*.pop_debug_group.?(cp),
                    .insert_debug_marker => |l| cp.*.insert_debug_marker.?(cp, rec.label(l)),
                }
            }
            cp.*.end.?(cp);
            submit[n] = enc.*.finish.?(enc);
            n += 1;
        }
    }
    if (n > 0) {
        st.device.queue_submit.?(st.device, st.queue, &submit, n);
        var i: u32 = 0;
        while (i < n) : (i += 1) submit[i].*.destroy.?(submit[i]);
        @memset(st.cmd_valid[0..], false);
    }
    var pe: u32 = 0;
    while (pe < rc.NUM_PRECREATED_ENCODERS) : (pe += 1) {
        const enc = st.cmd_encoders[pe];
        enc.*.destroy.?(enc);
    }
    st.frame_live = false;
    if (st.find("backbuffer")) |bb| bb.view = c.KE_GPU_INVALID_HANDLE;
    const presented = st.target.present.?(st.target, out_error);
    st.device.queue_poll.?(st.device, st.queue);
    return @intFromBool(presented);
}

/// Copies the bytes into the upload arena and queues a record for `endFrame` to write them to
/// the buffer. May be called from any worker between `beginFrame` and `endFrame`: the record and
/// the arena range are reserved with atomic counters before the copy. Nothing is returned, so an
/// upload dropped for the record limit or the arena end, or with a zero size or null data, is
/// silent.
pub fn uploadBuffer(self: [*c]c.ke_render_service, buffer: c.ke_gpu_buffer, offset: u64, data: ?*const anyopaque, size: usize) callconv(.c) void {
    if (size == 0 or data == null) return;
    const st = rc.coreOf(self);
    const idx = st.upload_count.fetchAdd(1, .monotonic);
    if (idx >= rc.MAX_UPLOADS) return;
    const aoff = st.upload_arena_offset.fetchAdd(size, .monotonic);
    if (aoff + size > st.upload_arena.len) return;
    const src: [*]const u8 = @ptrCast(data);
    @memcpy(st.upload_arena[aoff .. aoff + size], src[0..size]);
    st.upload_records[idx] = .{ .buffer = buffer, .gpu_offset = offset, .arena_offset = aoff, .size = size };
}
