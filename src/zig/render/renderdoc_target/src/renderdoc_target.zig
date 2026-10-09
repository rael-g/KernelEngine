//! This file wraps another render target and brackets the chosen frames with a RenderDoc capture,
//! forwarding everything else. `RenderdocTarget` holds the borrowed inner target, the RenderDoc
//! function table, the window of frames to capture, a frame counter and whether a capture is open.
//!
//! RenderDoc is used only if it is already in the process: `loadedApi` finds its entry point
//! through `loadedGetApi` and `ke_gpu_render_target_renderdoc_create` passes the table to `create`,
//! which validates its arguments before allocating. Each frame, `acquire` opens a capture before
//! the inner acquire when `chosen` accepts the counter, and `present` closes it. `destroy` discards
//! a capture still open.

const std = @import("std");
const builtin = @import("builtin");

pub const std_options: std.Options = .{ .signal_stack_size = null };

const c = @cImport({
    @cInclude("kernel_engine/render/gpu/gpu_render_target.h");
    @cInclude("kernel_engine/render/renderdoc_target/gpu_render_target_renderdoc_create.h");
    @cInclude("renderdoc_app.h");
});

const heap = @import("heap");
const gpa = heap.gpa;
const E = @import("kerror").Errors(c);

const Api = c.RENDERDOC_API_1_4_0;

/// The state behind a handle: `vtable.handle` points back at it, which is how `of` recovers it from
/// the vtable pointer callers hold. `capturing` is true only between an `acquire` that opened a
/// capture and the `present` or `destroy` that closes it. `create` allocates it; `destroy` frees.
const RenderdocTarget = struct {
    vtable: c.ke_gpu_render_target,
    inner: *c.ke_gpu_render_target,
    api: *Api,
    first_frame: u32,
    frame_count: u32,
    frame: u32,
    capturing: bool,
};

fn of(self: [*c]c.ke_gpu_render_target) *RenderdocTarget {
    return @ptrCast(@alignCast(self.*.handle));
}

/// True while the frame counter lies inside the window that starts at `first_frame` and spans
/// `frame_count` frames.
fn chosen(t: *const RenderdocTarget) bool {
    return t.frame >= t.first_frame and t.frame - t.first_frame < t.frame_count;
}

/// Runs at the start of each frame. A capture it starts stays open until `present` ends it or
/// `destroy` discards it, and is discarded here when the inner target yields no view.
fn acquire(self: [*c]c.ke_gpu_render_target, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_gpu_texture_view {
    const t = of(self);
    const capture = chosen(t) and !t.capturing;
    if (capture) t.api.StartFrameCapture.?(null, null);
    const view = t.inner.acquire.?(t.inner, out_error);
    if (view == c.KE_GPU_INVALID_HANDLE) {
        if (capture) _ = t.api.DiscardFrameCapture.?(null, null);
        return view;
    }
    if (capture) t.capturing = true;
    return view;
}

/// Runs at the end of each frame. The open capture is ended whether or not the inner `present`
/// succeeded; `frame` moves on only when it did, so a failed present keeps the frame number.
fn present(self: [*c]c.ke_gpu_render_target, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const t = of(self);
    const presented = t.inner.present.?(t.inner, out_error);
    if (t.capturing) {
        _ = t.api.EndFrameCapture.?(null, null);
        t.capturing = false;
    }
    if (presented) t.frame +%= 1;
    return presented;
}

fn size(self: [*c]c.ke_gpu_render_target, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
    const t = of(self);
    t.inner.size.?(t.inner, out_w, out_h);
}

fn format(self: [*c]c.ke_gpu_render_target) callconv(.c) c.ke_gpu_texture_format {
    const t = of(self);
    return t.inner.format.?(t.inner);
}

/// Runs when the handle is released. A capture still open is discarded rather than ended, and the
/// borrowed inner target is not destroyed.
fn destroy(self: [*c]c.ke_gpu_render_target) callconv(.c) void {
    const t = of(self);
    if (t.capturing) _ = t.api.DiscardFrameCapture.?(null, null);
    gpa.destroy(t);
}

/// The RenderDoc entry point that fills a function table for a requested version.
const GetApi = *const fn (c.RENDERDOC_Version, *?*anyopaque) callconv(.c) c_int;

extern "kernel32" fn GetModuleHandleA(name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetProcAddress(module: *anyopaque, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;

/// Never loads RenderDoc itself: a library not already in the process yields null.
fn loadedGetApi() ?GetApi {
    const symbol: ?*anyopaque = switch (builtin.target.os.tag) {
        .windows => blk: {
            const module = GetModuleHandleA("renderdoc.dll") orelse break :blk null;
            break :blk GetProcAddress(module, "RENDERDOC_GetAPI");
        },
        .linux => blk: {
            const module = std.c.dlopen("librenderdoc.so", .{ .NOW = true, .NOLOAD = true }) orelse break :blk null;
            break :blk std.c.dlsym(module, "RENDERDOC_GetAPI");
        },
        else => null,
    };
    return @ptrCast(@alignCast(symbol orelse return null));
}

/// The only source of the table `ke_gpu_render_target_renderdoc_create` passes to `create`; a null
/// table there is reported as RenderDoc not being loaded.
fn loadedApi() ?*Api {
    const get = loadedGetApi() orelse return null;
    var api: ?*anyopaque = null;
    if (get(c.eRENDERDOC_API_Version_1_4_0, &api) != 1) return null;
    return @ptrCast(@alignCast(api orelse return null));
}

/// Holds the checks and the allocation behind `ke_gpu_render_target_renderdoc_create`, taking the
/// table as a parameter rather than looking it up. A failed check or an allocation failure fills
/// `out_error` and returns a null `ref`, with nothing left allocated.
fn create(
    inner: ?*c.ke_gpu_render_target,
    params: ?*const c.ke_gpu_render_target_renderdoc_params,
    api: ?*Api,
    out_error: [*c][*c]c.ke_error,
) c.ke_gpu_render_target_handle {
    const empty: c.ke_gpu_render_target_handle = .{ .ref = null, .destroy = null };
    const target = inner orelse {
        E.fail(out_error, .invalid_argument, "renderdoc target: the inner target is required", @src());
        return empty;
    };
    const p = params orelse {
        E.fail(out_error, .invalid_argument, "renderdoc target: params are required", @src());
        return empty;
    };
    const rdoc = api orelse {
        E.fail(out_error, .not_found, "renderdoc target: RenderDoc is not loaded into this process", @src());
        return empty;
    };
    const t = gpa.create(RenderdocTarget) catch {
        E.fail(out_error, .out_of_memory, "renderdoc target: out of memory", @src());
        return empty;
    };
    t.* = .{
        .vtable = .{ .handle = t, .acquire = acquire, .present = present, .size = size, .format = format },
        .inner = target,
        .api = rdoc,
        .first_frame = p.first_frame,
        .frame_count = p.frame_count,
        .frame = 0,
        .capturing = false,
    };
    return .{ .ref = &t.vtable, .destroy = destroy };
}

/// Wraps `inner` with the table of the RenderDoc already loaded in the process. Fails with the
/// errors of `create`, among them not found when RenderDoc is not loaded.
export fn ke_gpu_render_target_renderdoc_create(
    inner: ?*c.ke_gpu_render_target,
    params: ?*const c.ke_gpu_render_target_renderdoc_params,
    out_error: [*c][*c]c.ke_error,
) c.ke_gpu_render_target_handle {
    return create(inner, params, loadedApi(), out_error);
}

const testing = std.testing;

const Fake = struct {
    var started: u32 = 0;
    var ended: u32 = 0;
    var discarded: u32 = 0;
    var open: bool = false;
    var acquired_while_open: u32 = 0;
    var presented_while_open: u32 = 0;

    vtable: c.ke_gpu_render_target,
    empty_frames: u32,
    presented: u32,

    fn init(self: *Fake, empty_frames: u32) *Api {
        started = 0;
        ended = 0;
        discarded = 0;
        open = false;
        acquired_while_open = 0;
        presented_while_open = 0;
        self.* = .{
            .vtable = .{ .handle = self, .acquire = innerAcquire, .present = innerPresent, .size = innerSize, .format = innerFormat },
            .empty_frames = empty_frames,
            .presented = 0,
        };
        api = std.mem.zeroes(Api);
        api.StartFrameCapture = start;
        api.EndFrameCapture = end;
        api.DiscardFrameCapture = discard;
        return &api;
    }

    var api: Api = undefined;

    fn start(_: c.RENDERDOC_DevicePointer, _: c.RENDERDOC_WindowHandle) callconv(.c) void {
        started += 1;
        open = true;
    }

    fn end(_: c.RENDERDOC_DevicePointer, _: c.RENDERDOC_WindowHandle) callconv(.c) u32 {
        ended += 1;
        open = false;
        return 1;
    }

    fn discard(_: c.RENDERDOC_DevicePointer, _: c.RENDERDOC_WindowHandle) callconv(.c) u32 {
        discarded += 1;
        open = false;
        return 1;
    }

    fn selfOf(target: [*c]c.ke_gpu_render_target) *Fake {
        return @ptrCast(@alignCast(target.*.handle));
    }

    fn innerAcquire(target: [*c]c.ke_gpu_render_target, _: [*c][*c]c.ke_error) callconv(.c) c.ke_gpu_texture_view {
        const self = selfOf(target);
        if (self.empty_frames > 0) {
            self.empty_frames -= 1;
            return c.KE_GPU_INVALID_HANDLE;
        }
        if (open) acquired_while_open += 1;
        return 9;
    }

    fn innerPresent(target: [*c]c.ke_gpu_render_target, _: [*c][*c]c.ke_error) callconv(.c) bool {
        if (open) presented_while_open += 1;
        selfOf(target).presented += 1;
        return true;
    }

    fn innerSize(_: [*c]c.ke_gpu_render_target, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
        out_w.* = 320;
        out_h.* = 240;
    }

    fn innerFormat(_: [*c]c.ke_gpu_render_target) callconv(.c) c.ke_gpu_texture_format {
        return c.KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM;
    }
};

fn frame(t: *c.ke_gpu_render_target) !void {
    try testing.expectEqual(@as(c.ke_gpu_texture_view, 9), t.acquire.?(t, null));
    try testing.expect(t.present.?(t, null));
}

test "only the chosen frames are captured, each from before its acquire until after its present" {
    var inner: Fake = undefined;
    const api = inner.init(0);
    const p = c.ke_gpu_render_target_renderdoc_params{ .first_frame = 1, .frame_count = 2 };
    const h = create(&inner.vtable, &p, api, null);
    const t = h.ref orelse return error.TestUnexpectedResult;
    defer h.destroy.?(t);

    try frame(t);
    try testing.expectEqual(@as(u32, 0), Fake.started);
    try frame(t);
    try frame(t);
    try frame(t);

    try testing.expectEqual(@as(u32, 2), Fake.started);
    try testing.expectEqual(@as(u32, 2), Fake.ended);
    try testing.expectEqual(@as(u32, 0), Fake.discarded);
    try testing.expectEqual(@as(u32, 2), Fake.acquired_while_open);
    try testing.expectEqual(@as(u32, 2), Fake.presented_while_open);
    try testing.expectEqual(@as(u32, 4), inner.presented);
}

test "a chosen frame the inner target has nothing to draw into is discarded and captured on the next acquire" {
    var inner: Fake = undefined;
    const api = inner.init(1);
    const p = c.ke_gpu_render_target_renderdoc_params{ .first_frame = 0, .frame_count = 1 };
    const h = create(&inner.vtable, &p, api, null);
    const t = h.ref orelse return error.TestUnexpectedResult;
    defer h.destroy.?(t);

    try testing.expectEqual(@as(c.ke_gpu_texture_view, c.KE_GPU_INVALID_HANDLE), t.*.acquire.?(t, null));
    try testing.expectEqual(@as(u32, 1), Fake.discarded);
    try testing.expectEqual(@as(u32, 0), Fake.ended);

    try frame(t);
    try testing.expectEqual(@as(u32, 2), Fake.started);
    try testing.expectEqual(@as(u32, 1), Fake.ended);
}

test "size and format are the inner target's" {
    var inner: Fake = undefined;
    const api = inner.init(0);
    const p = c.ke_gpu_render_target_renderdoc_params{ .first_frame = 0, .frame_count = 0 };
    const h = create(&inner.vtable, &p, api, null);
    const t = h.ref orelse return error.TestUnexpectedResult;
    defer h.destroy.?(t);

    var w: u32 = 0;
    var ht: u32 = 0;
    t.*.size.?(t, &w, &ht);
    try testing.expectEqual(@as(u32, 320), w);
    try testing.expectEqual(@as(u32, 240), ht);
    try testing.expectEqual(@as(c.ke_gpu_texture_format, c.KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM), t.*.format.?(t));
    try frame(t);
    try testing.expectEqual(@as(u32, 0), Fake.started);
}

test "a target destroyed with a capture open discards it" {
    var inner: Fake = undefined;
    const api = inner.init(0);
    const p = c.ke_gpu_render_target_renderdoc_params{ .first_frame = 0, .frame_count = 1 };
    const h = create(&inner.vtable, &p, api, null);
    const t = h.ref orelse return error.TestUnexpectedResult;

    try testing.expectEqual(@as(c.ke_gpu_texture_view, 9), t.*.acquire.?(t, null));
    h.destroy.?(t);
    try testing.expectEqual(@as(u32, 1), Fake.discarded);
    try heap.expectNoLeaks();
}

test "creation is refused without an inner target, without params, and when RenderDoc is not loaded" {
    var inner: Fake = undefined;
    const api = inner.init(0);
    const p = c.ke_gpu_render_target_renderdoc_params{ .first_frame = 0, .frame_count = 1 };

    var err: [*c]c.ke_error = null;
    try testing.expect(create(null, &p, api, &err).ref == null);
    try testing.expect(err != null and err.*.type == E.typeOf(.invalid_argument));

    err = null;
    try testing.expect(create(&inner.vtable, null, api, &err).ref == null);
    try testing.expect(err != null and err.*.type == E.typeOf(.invalid_argument));

    err = null;
    try testing.expect(ke_gpu_render_target_renderdoc_create(&inner.vtable, &p, &err).ref == null);
    try testing.expect(err != null and err.*.type == E.typeOf(.not_found));
    try heap.expectNoLeaks();
}
