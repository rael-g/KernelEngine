const rc = @import("render_service.zig");
const c = rc.c;

// Frame begin/end + the deferred-upload recorder. wgpuQueueWriteBuffer and
// command-encoder/command-buffer creation are NOT safe to call concurrently
// with parallel pass recording on wgpu-native — this is the one place per
// frame those run single-threaded, ordered so the data/commands land before
// the submit.

pub fn beginFrame(self: [*c]c.ke_render_service, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_bool {
    _ = out_error;
    const st = rc.coreOf(self);
    @memset(st.cmd_valid[0..], false); // open the frame: no pass has recorded yet
    for (&st.compute_records) |*r| {
        r.valid = false;
        r.count = 0;
    }
    st.upload_count.store(0, .monotonic); // reset the deferred-upload collector
    st.upload_arena_offset.store(0, .monotonic);
    // uiReset happens at the END of the ui pass (uiDraw), not here — see uiDraw.
    // Resetting here would wipe quads a system in an EARLIER phase (e.g. Update)
    // queued for THIS frame's ui pass to draw, since begin_frame is itself an
    // ordinary render-phase system with no ordering guarantee relative to systems
    // registered by other modules ahead of the render module in load order.
    // Pre-create this frame's command encoders single-threaded; parallel passes
    // record into theirs without calling the non-thread-safe create function.
    var pe: u32 = 0;
    while (pe < rc.NUM_PRECREATED_ENCODERS) : (pe += 1) {
        st.cmd_encoders[pe] = st.device.create_command_encoder.?(st.device);
    }
    if (st.surface) |surf| {
        surf.current_size.?(surf, &st.backbuffer_w, &st.backbuffer_h);
        const view = surf.acquire_current_texture_view.?(surf);
        if (view == c.KE_GPU_INVALID_HANDLE) return 0;
        if (st.find("backbuffer")) |bb| bb.view = view;
    }
    return 1;
}

pub fn endFrame(self: [*c]c.ke_render_service, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_bool {
    _ = out_error;
    const st = rc.coreOf(self);

    // Flush the frame's deferred uploads single-threaded — wgpuQueueWriteBuffer is
    // not safe concurrently with pass recording, so this is the only place it runs.
    // Queue writes are ordered before the submit below, so the data lands in time.
    const ucount = @min(st.upload_count.load(.monotonic), rc.MAX_UPLOADS);
    var u: u32 = 0;
    while (u < ucount) : (u += 1) {
        const r = st.upload_records[u];
        st.device.write_buffer.?(st.device, r.buffer, r.gpu_offset, &st.upload_arena[r.arena_offset], r.size);
    }

    // Build the frame's command buffers single-threaded (the device's command-buffer
    // registry is not thread-safe), in ascending slot order = dependency order. A
    // render slot finishes its parked encoder; a compute slot replays its accumulated
    // recording into that slot's encoder here — the one place compute recording runs,
    // so it never races a concurrently-recording render pass.
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
            const cp = enc.*.begin_compute_pass.?(enc);
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
    // Release this frame's pre-created encoders (whether or not a pass used them).
    var pe: u32 = 0;
    while (pe < rc.NUM_PRECREATED_ENCODERS) : (pe += 1) {
        const enc = st.cmd_encoders[pe];
        enc.*.destroy.?(enc);
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

// Records a deferred upload — lock-free, callable from any pass thread. The index
// and the arena slice are each reserved with an atomic bump, then the data is copied
// in. end_frame replays the records single-threaded (wgpuQueueWriteBuffer is unsafe
// concurrently with pass recording on wgpu-native).
pub fn uploadBuffer(self: [*c]c.ke_render_service, buffer: c.ke_gpu_buffer, offset: u64, data: ?*const anyopaque, size: usize) callconv(.c) void {
    if (size == 0 or data == null) return;
    const st = rc.coreOf(self);
    const idx = st.upload_count.fetchAdd(1, .monotonic);
    if (idx >= rc.MAX_UPLOADS) return; // overflow — raise MAX_UPLOADS if ever hit
    const aoff = st.upload_arena_offset.fetchAdd(size, .monotonic);
    if (aoff + size > st.upload_arena.len) return; // arena overflow — raise the size
    const src: [*]const u8 = @ptrCast(data);
    @memcpy(st.upload_arena[aoff .. aoff + size], src[0..size]);
    st.upload_records[idx] = .{ .buffer = buffer, .gpu_offset = offset, .arena_offset = aoff, .size = size };
}
