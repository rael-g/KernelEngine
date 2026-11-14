//! Opens and closes a frame of the render service, and carries the buffer uploads queued during it.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_gpu = @import("abi_render_gpu");
const std = @import("std");
const heap = @import("heap");
const rc = @import("render_service.zig");
const abi_render = @import("abi_render");
const abi_result = @import("abi_result");
const R = rc.R;

/// The `begin_frame` slot. It forgets the previous frame's uploads and the blit's sets before it
/// acquires the target, so a failed acquire leaves the frame closed and returns the target's code,
/// and a target with nothing to draw into leaves it closed, writes the invalid view and succeeds.
/// Once it has a view, it reads the target's size and the frame is live.
pub fn beginFrame(self: [*c]abi_render.c.ke_render_service, out_view: [*c]abi_asset_resolver.c.ke_gpu_texture_view) callconv(.c) abi_result.c.ke_result {
    if (self == null or out_view == null) return R.code(error.InvalidArgument);
    out_view.* = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    const st = rc.coreOf(self);
    st.frame_live = false;
    st.blit.releaseSets(st.binder);
    st.upload_count.store(0, .monotonic);
    st.upload_arena_offset.store(0, .monotonic);
    var view: abi_asset_resolver.c.ke_gpu_texture_view = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    const acquired = st.target.acquire.?(st.target, &view);
    if (acquired != R.ok or view == abi_render_gpu.c.KE_GPU_INVALID_HANDLE) return acquired;
    st.target.size.?(st.target, &st.backbuffer_w, &st.backbuffer_h);
    st.frame_live = true;
    out_view.* = view;
    return R.ok;
}

/// The `submit_uploads` slot: writes every upload recorded since the frame began. Does nothing when
/// no frame is live.
pub fn submitUploads(self: [*c]abi_render.c.ke_render_service) callconv(.c) void {
    if (self == null) return;
    const st = rc.coreOf(self);
    if (!st.frame_live) return;
    flushUploads(st);
}

/// The `end_frame` slot: presents the target and polls the queue whatever the present returned,
/// and the frame stops being live. Succeeds doing nothing when no frame is live.
pub fn endFrame(self: [*c]abi_render.c.ke_render_service) callconv(.c) abi_result.c.ke_result {
    if (self == null) return R.code(error.InvalidArgument);
    const st = rc.coreOf(self);
    if (!st.frame_live) return R.ok;
    st.frame_live = false;
    const presented = st.target.present.?(st.target);
    st.device.queue_poll.?(st.device, st.queue);
    return presented;
}

/// The `blit` slot.
pub fn blit(self: [*c]abi_render.c.ke_render_service, pass: [*c]abi_render_gpu.c.ke_gpu_render_pass, source: abi_asset_resolver.c.ke_gpu_texture_view, target_format: abi_render_gpu.c.ke_gpu_texture_format) callconv(.c) void {
    if (self == null or pass == null) return;
    const st = rc.coreOf(self);
    _ = st.blit.draw(self, st.binder, pass, source, target_format);
}

/// The `backbuffer_size` slot.
pub fn backbufferSize(self: [*c]abi_render.c.ke_render_service, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
    if (self == null) return;
    const st = rc.coreOf(self);
    if (out_w != null) out_w.* = st.backbuffer_w;
    if (out_h != null) out_h.* = st.backbuffer_h;
}

/// The `backbuffer_format` slot; asks the render target on every call.
pub fn backbufferFormat(self: [*c]abi_render.c.ke_render_service) callconv(.c) abi_render_gpu.c.ke_gpu_texture_format {
    if (self == null) return abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_INVALID;
    const st = rc.coreOf(self);
    return st.target.format.?(st.target);
}


/// Writes the frame's uploads in the order they were reserved, the arena's first and then the
/// spilled ones, and frees the spilled blocks. When the frame needed more records or arena bytes
/// than there were, both grow to what it asked for, so the next frame of that size does not spill.
/// Runs single-threaded, before the frame's work is submitted.
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

/// Copies the bytes into the upload arena and queues a record for `submitUploads` to write them to
/// the buffer. May be called from any worker between `beginFrame` and `submitUploads`: the record and
/// the arena range are reserved with atomic counters before the copy. An upload that finds either
/// full is copied into a block of its own and pushed onto the spill list instead; it is lost only
/// when that block cannot be allocated. A zero size or null data does nothing.
pub fn uploadBuffer(self: [*c]abi_render.c.ke_render_service, buffer: abi_asset_resolver.c.ke_gpu_buffer, offset: u64, data: ?*const anyopaque, size: usize) callconv(.c) void {
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

fn spill(st: *rc.CoreState, buffer: abi_asset_resolver.c.ke_gpu_buffer, offset: u64, bytes: []const u8) void {
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
