//! Opens and closes a frame of the render service, and carries the buffer uploads queued during it.

const std = @import("std");
const heap = @import("heap");
const rc = @import("render_service.zig");
const resource_table = @import("resource_table.zig");
const frame_chain = @import("frame_chain.zig");
const c = rc.c;

/// Opens a frame. The previous frame's ended passes, compute records and upload counters are
/// cleared before the target is acquired, so a failed acquire leaves the frame closed and
/// returns zero with the target's error. Once it has returned one, the backbuffer size is read
/// from the target, the "backbuffer" entry holds the acquired view, the chain's links are given
/// their textures, the clear of the frame's color and depth is recorded and the frame is live.
pub fn beginFrame(self: [*c]c.ke_render_service, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const st = rc.coreOf(self);
    st.frame_live = false;
    dropClear(st);
    st.blit.releaseSets(st.binder);
    st.ended_count.store(0, .monotonic);
    st.compute_count.store(0, .monotonic);
    for (&st.compute_records) |*r| {
        r.cmds.clearRetainingCapacity();
        r.offsets.clearRetainingCapacity();
        r.labels.clearRetainingCapacity();
    }
    st.upload_count.store(0, .monotonic);
    st.upload_arena_offset.store(0, .monotonic);
    const view = st.target.acquire.?(st.target, out_error);
    if (view == c.KE_GPU_INVALID_HANDLE) return false;
    st.target.size.?(st.target, &st.backbuffer_w, &st.backbuffer_h);
    resource_table.resizeRelative(st);
    if (st.find("backbuffer")) |bb| bb.view = view;
    frame_chain.assign(st);
    st.clear_pass = frame_chain.recordClear(st);
    st.frame_live = true;
    return true;
}

fn dropClear(st: *rc.CoreState) void {
    const enc = st.clear_pass orelse return;
    enc.destroy.?(enc.ref);
    st.clear_pass = null;
}

/// The encoders of one frame in the order they are submitted. An encoder added here is finished
/// and destroyed by `submit`, whether its finish succeeds or not.
const Submission = struct {
    encoders: [rc.MAX_CMD_BUFFERS * 2 + 2]c.ke_gpu_command_encoder_handle = undefined,
    records: [rc.MAX_CMD_BUFFERS * 2 + 2]?*rc.ComputeRecord = undefined,
    count: usize = 0,

    fn add(self: *Submission, enc: ?c.ke_gpu_command_encoder_handle, rec: ?*rc.ComputeRecord) void {
        const e = enc orelse return;
        if (self.count == self.encoders.len) {
            e.destroy.?(e.ref);
            return;
        }
        self.encoders[self.count] = e;
        self.records[self.count] = rec;
        self.count += 1;
    }

    fn submit(self: *Submission, st: *rc.CoreState) void {
        var finished: [rc.MAX_CMD_BUFFERS * 2 + 2]c.ke_gpu_command_buffer_handle = undefined;
        var cmds: [rc.MAX_CMD_BUFFERS * 2 + 2][*c]c.ke_gpu_command_buffer = undefined;
        var n: u32 = 0;
        for (self.encoders[0..self.count], self.records[0..self.count]) |enc, rec| {
            if (rec) |r| replay(enc.ref, r);
            const cmd = enc.ref.*.finish.?(enc.ref, null);
            if (cmd.ref == null) continue;
            finished[n] = cmd;
            cmds[n] = cmd.ref;
            n += 1;
        }
        if (n > 0) st.device.queue_submit.?(st.device, st.queue, &cmds, n);
        for (finished[0..n]) |cmd| cmd.destroy.?(cmd.ref);
        for (self.encoders[0..self.count]) |enc| enc.destroy.?(enc.ref);
    }
};

/// Closes the frame. The queued uploads are written to their buffers before any command buffer
/// is finished. The clear of the frame goes first, then each pass outside the chain in the order
/// the passes ended, then the chain in its order: each link's passes in the order they ended, or,
/// for a link whose pass recorded nothing and whose target starts from a source, a draw of the
/// source into the target. Last comes the draw of the frame's color into the backbuffer. A compute
/// record is replayed on its pass's encoder before it is finished; an encoder whose finish fails
/// is left out. The command buffers are submitted in one call and destroyed with their encoders,
/// and the frame stops being live. Returns the result of the present, with the target's error on
/// failure; the queue is polled whatever it returned. Returns zero and does nothing when no frame
/// is live.
pub fn endFrame(self: [*c]c.ke_render_service, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const st = rc.coreOf(self);
    if (!st.frame_live) return false;

    flushUploads(st);

    const ended = st.ended[0..@min(st.ended_count.load(.monotonic), rc.MAX_CMD_BUFFERS)];
    var sub: Submission = .{};
    sub.add(st.clear_pass, null);
    st.clear_pass = null;
    for (ended) |pass| {
        if (pass.chain == c.KE_RENDER_CHAIN_NONE) sub.add(pass.encoder, pass.record);
    }
    for (st.chain.links.items) |*link| {
        var any = false;
        for (ended) |pass| {
            if (pass.chain != link.id) continue;
            sub.add(pass.encoder, pass.record);
            any = true;
        }
        if (!any and link.source != c.KE_GPU_INVALID_HANDLE)
            sub.add(frame_chain.recordBlit(st, link.source, link.target, link.target_format), null);
    }
    for (ended) |pass| {
        if (pass.chain != c.KE_RENDER_CHAIN_NONE and st.chain.find(pass.chain) == null) sub.add(pass.encoder, pass.record);
    }
    if (st.find("backbuffer")) |bb| sub.add(frame_chain.recordBlit(st, st.chain.final, bb.view, bb.format), null);
    sub.submit(st);

    st.ended_count.store(0, .monotonic);
    st.frame_live = false;
    if (st.find("backbuffer")) |bb| bb.view = c.KE_GPU_INVALID_HANDLE;
    const presented = st.target.present.?(st.target, out_error);
    st.device.queue_poll.?(st.device, st.queue);
    return presented;
}

fn replay(enc: *c.ke_gpu_command_encoder, rec: *const rc.ComputeRecord) void {
    const cp = enc.*.begin_compute_pass.?(enc, &c.ke_gpu_compute_pass_params{ .label = rec.label(rec.pass_label) });
    for (rec.cmds.items) |cmd| {
        switch (cmd) {
            .set_pipeline => |p| cp.*.set_pipeline.?(cp, p),
            .set_bind_group => |b| {
                if (b.count > 0)
                    cp.*.set_bind_group.?(cp, b.index, b.bg, rec.offsets.items[b.first_offset..].ptr, b.count)
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
}

/// Writes the frame's uploads in the order they were reserved, the arena's first and then the
/// spilled ones, and frees the spilled blocks. When the frame needed more records or arena bytes
/// than there were, both grow to what it asked for, so the next frame of that size does not spill.
/// Runs single-threaded, at the end of the frame.
fn flushUploads(st: *rc.CoreState) void {
    const requested = st.upload_count.load(.monotonic);
    const bytes = st.upload_arena_offset.load(.monotonic);
    for (st.upload_records[0..@min(requested, st.upload_records.len)]) |r| {
        if (r.size == 0) continue;
        st.device.write_buffer.?(st.device, r.buffer, r.gpu_offset, &st.upload_arena[r.arena_offset], r.size);
    }

    var reversed: ?*rc.SpilledUpload = null;
    var node = st.upload_spill.swap(null, .acquire);
    while (node) |n| {
        node = n.next;
        n.next = reversed;
        reversed = n;
    }
    while (reversed) |n| {
        reversed = n.next;
        st.device.write_buffer.?(st.device, n.buffer, n.gpu_offset, n.data.ptr, n.data.len);
        heap.gpa.free(n.data);
        heap.gpa.destroy(n);
    }

    if (requested > st.upload_records.len) {
        if (heap.gpa.realloc(st.upload_records, std.math.ceilPowerOfTwoAssert(usize, requested))) |grown| st.upload_records = grown else |_| {}
    }
    if (bytes > st.upload_arena.len) {
        if (heap.gpa.realloc(st.upload_arena, std.math.ceilPowerOfTwoAssert(usize, bytes))) |grown| st.upload_arena = grown else |_| {}
    }
}

/// Copies the bytes into the upload arena and queues a record for `endFrame` to write them to
/// the buffer. May be called from any worker between `beginFrame` and `endFrame`: the record and
/// the arena range are reserved with atomic counters before the copy. An upload that finds either
/// full is copied into a block of its own and pushed onto the spill list instead; it is lost only
/// when that block cannot be allocated. A zero size or null data does nothing.
pub fn uploadBuffer(self: [*c]c.ke_render_service, buffer: c.ke_gpu_buffer, offset: u64, data: ?*const anyopaque, size: usize) callconv(.c) void {
    if (size == 0 or data == null) return;
    const st = rc.coreOf(self);
    const src: [*]const u8 = @ptrCast(data);
    const idx = st.upload_count.fetchAdd(1, .monotonic);
    const aoff = st.upload_arena_offset.fetchAdd(size, .monotonic);
    if (idx < st.upload_records.len) {
        if (aoff + size <= st.upload_arena.len) {
            @memcpy(st.upload_arena[aoff .. aoff + size], src[0..size]);
            st.upload_records[idx] = .{ .buffer = buffer, .gpu_offset = offset, .arena_offset = aoff, .size = size };
            return;
        }
        st.upload_records[idx] = .{ .buffer = buffer, .gpu_offset = offset, .arena_offset = 0, .size = 0 };
    }
    spill(st, buffer, offset, src[0..size]);
}

fn spill(st: *rc.CoreState, buffer: c.ke_gpu_buffer, offset: u64, bytes: []const u8) void {
    const data = heap.gpa.dupe(u8, bytes) catch return;
    const node = heap.gpa.create(rc.SpilledUpload) catch {
        heap.gpa.free(data);
        return;
    };
    node.* = .{ .next = null, .buffer = buffer, .gpu_offset = offset, .data = data };
    var head = st.upload_spill.load(.monotonic);
    while (true) {
        node.next = head;
        head = st.upload_spill.cmpxchgWeak(head, node, .release, .monotonic) orelse return;
    }
}
