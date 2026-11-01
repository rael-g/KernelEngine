//! A render target that wraps another one and brackets the chosen frames with a RenderDoc capture,
//! forwarding everything else to the inner target.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_gpu = @import("abi_render_gpu");
const std = @import("std");
const builtin = @import("builtin");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_gpu_render_target_renderdoc").logFn };

const c = @import("c");
const abi_gpu_render_target_renderdoc_factory = @import("abi_gpu_render_target_renderdoc_factory");
const abi_render = @import("abi_render");
const abi_result = @import("abi_result");

const heap = @import("heap");
const gpa = heap.gpa;
const R = @import("result").Result(.{});
const log = std.log.scoped(.renderdoc_target);

const Api = c.RENDERDOC_API_1_4_0;

/// The state behind a handle: `vtable.handle` points back at it, which is how `of` recovers it from
/// the vtable pointer callers hold. `capturing` is true only between an `acquire` that opened a
/// capture and the `present` or `destroy` that closes it. `create` allocates it; `destroy` frees.
const RenderdocTarget = struct {
    vtable: abi_render_gpu.c.ke_gpu_render_target,
    inner: *abi_render_gpu.c.ke_gpu_render_target,
    api: *Api,
    first_frame: u32,
    frame_count: u32,
    frame: u32,
    capturing: bool,
};

fn of(self: [*c]abi_render_gpu.c.ke_gpu_render_target) *RenderdocTarget {
    return @ptrCast(@alignCast(self.*.handle));
}

/// True while the frame counter lies inside the window that starts at `first_frame` and spans
/// `frame_count` frames.
fn chosen(t: *const RenderdocTarget) bool {
    return t.frame >= t.first_frame and t.frame - t.first_frame < t.frame_count;
}

/// Runs at the start of each frame. RenderDoc is told to start a capture before the inner `acquire`
/// when `chosen` accepts the frame counter. A capture it starts stays open until `present` ends it
/// or `destroy` discards it, and is discarded here when the inner target yields no view. The code
/// and the view are the inner target's.
fn acquire(self: [*c]abi_render_gpu.c.ke_gpu_render_target, out_view: [*c]abi_asset_resolver.c.ke_gpu_texture_view) callconv(.c) abi_result.c.ke_result {
    const out = out_view orelse return R.code(error.InvalidArgument);
    out.* = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    if (self == null) return R.code(error.InvalidArgument);
    const t = of(self);
    const capture = chosen(t) and !t.capturing;
    if (capture) t.api.StartFrameCapture.?(null, null);
    const inner_code = t.inner.acquire.?(t.inner, out);
    if (inner_code != R.ok or out.* == abi_render_gpu.c.KE_GPU_INVALID_HANDLE) {
        if (capture) _ = t.api.DiscardFrameCapture.?(null, null);
        return inner_code;
    }
    if (capture) t.capturing = true;
    return R.ok;
}

/// Runs at the end of each frame. The open capture is ended whether or not the inner `present`
/// succeeded; `frame` moves on only when it did, so a failed present keeps the frame number. The
/// code is the inner target's.
fn present(self: [*c]abi_render_gpu.c.ke_gpu_render_target) callconv(.c) abi_result.c.ke_result {
    if (self == null) return R.code(error.InvalidArgument);
    const t = of(self);
    const presented = t.inner.present.?(t.inner);
    if (t.capturing) {
        _ = t.api.EndFrameCapture.?(null, null);
        t.capturing = false;
    }
    if (presented == R.ok) t.frame +%= 1;
    return presented;
}

/// Forwards to the inner target.
fn size(self: [*c]abi_render_gpu.c.ke_gpu_render_target, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
    const t = of(self);
    t.inner.size.?(t.inner, out_w, out_h);
}

/// Forwards to the inner target.
fn format(self: [*c]abi_render_gpu.c.ke_gpu_render_target) callconv(.c) abi_render_gpu.c.ke_gpu_texture_format {
    const t = of(self);
    return t.inner.format.?(t.inner);
}

/// Runs when the handle is released. A capture still open is discarded rather than ended, and the
/// borrowed inner target is not destroyed.
fn destroy(self: [*c]abi_render_gpu.c.ke_gpu_render_target) callconv(.c) void {
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
/// table as a parameter rather than looking it up. A missing inner target or params fail as an
/// invalid argument, a missing table as not found and a failed allocation as out of memory, with
/// nothing left allocated.
fn create(
    inner: ?*abi_render_gpu.c.ke_gpu_render_target,
    params: ?*const abi_gpu_render_target_renderdoc_factory.c.ke_gpu_render_target_renderdoc_params,
    api: ?*Api,
) R.Error!abi_render_gpu.c.ke_gpu_render_target_handle {
    const target = inner orelse return error.InvalidArgument;
    const p = params orelse return error.InvalidArgument;
    const rdoc = api orelse {
        log.warn("RenderDoc is not loaded into this process", .{});
        return error.NotFound;
    };
    const t = try gpa.create(RenderdocTarget);
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
/// errors of `create`, among them not found when RenderDoc is not loaded, leaving the handle zeroed.
export fn ke_gpu_render_target_renderdoc_create(
    inner: ?*abi_render_gpu.c.ke_gpu_render_target,
    params: ?*const abi_gpu_render_target_renderdoc_factory.c.ke_gpu_render_target_renderdoc_params,
    out_target: [*c]abi_render_gpu.c.ke_gpu_render_target_handle,
) abi_result.c.ke_result {
    const out = out_target orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    out.* = create(inner, params, loadedApi()) catch |err| return R.code(err);
    return R.ok;
}

const testing = std.testing;

const Fake = struct {
    var started: u32 = 0;
    var ended: u32 = 0;
    var discarded: u32 = 0;
    var open: bool = false;
    var acquired_while_open: u32 = 0;
    var presented_while_open: u32 = 0;

    vtable: abi_render_gpu.c.ke_gpu_render_target,
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

    fn selfOf(target: [*c]abi_render_gpu.c.ke_gpu_render_target) *Fake {
        return @ptrCast(@alignCast(target.*.handle));
    }

    fn innerAcquire(target: [*c]abi_render_gpu.c.ke_gpu_render_target, out_view: [*c]abi_asset_resolver.c.ke_gpu_texture_view) callconv(.c) abi_result.c.ke_result {
        const self = selfOf(target);
        if (self.empty_frames > 0) {
            self.empty_frames -= 1;
            out_view.* = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
            return R.ok;
        }
        if (open) acquired_while_open += 1;
        out_view.* = 9;
        return R.ok;
    }

    fn innerPresent(target: [*c]abi_render_gpu.c.ke_gpu_render_target) callconv(.c) abi_result.c.ke_result {
        if (open) presented_while_open += 1;
        selfOf(target).presented += 1;
        return R.ok;
    }

    fn innerSize(_: [*c]abi_render_gpu.c.ke_gpu_render_target, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
        out_w.* = 320;
        out_h.* = 240;
    }

    fn innerFormat(_: [*c]abi_render_gpu.c.ke_gpu_render_target) callconv(.c) abi_render_gpu.c.ke_gpu_texture_format {
        return abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM;
    }
};

fn frame(t: *abi_render_gpu.c.ke_gpu_render_target) !void {
    try testing.expectEqual(@as(abi_asset_resolver.c.ke_gpu_texture_view, 9), try acquired(t));
    try R.check(t.present.?(t));
}

fn acquired(t: *abi_render_gpu.c.ke_gpu_render_target) !abi_asset_resolver.c.ke_gpu_texture_view {
    var view: abi_asset_resolver.c.ke_gpu_texture_view = undefined;
    try R.check(t.acquire.?(t, &view));
    return view;
}

test "only the chosen frames are captured, each from before its acquire until after its present" {
    var inner: Fake = undefined;
    const api = inner.init(0);
    const p = abi_gpu_render_target_renderdoc_factory.c.ke_gpu_render_target_renderdoc_params{ .first_frame = 1, .frame_count = 2 };
    const h = try create(&inner.vtable, &p, api);
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
    const p = abi_gpu_render_target_renderdoc_factory.c.ke_gpu_render_target_renderdoc_params{ .first_frame = 0, .frame_count = 1 };
    const h = try create(&inner.vtable, &p, api);
    const t = h.ref orelse return error.TestUnexpectedResult;
    defer h.destroy.?(t);

    try testing.expectEqual(@as(abi_asset_resolver.c.ke_gpu_texture_view, abi_render_gpu.c.KE_GPU_INVALID_HANDLE), try acquired(t));
    try testing.expectEqual(@as(u32, 1), Fake.discarded);
    try testing.expectEqual(@as(u32, 0), Fake.ended);

    try frame(t);
    try testing.expectEqual(@as(u32, 2), Fake.started);
    try testing.expectEqual(@as(u32, 1), Fake.ended);
}

test "size and format are the inner target's" {
    var inner: Fake = undefined;
    const api = inner.init(0);
    const p = abi_gpu_render_target_renderdoc_factory.c.ke_gpu_render_target_renderdoc_params{ .first_frame = 0, .frame_count = 0 };
    const h = try create(&inner.vtable, &p, api);
    const t = h.ref orelse return error.TestUnexpectedResult;
    defer h.destroy.?(t);

    var w: u32 = 0;
    var ht: u32 = 0;
    t.*.size.?(t, &w, &ht);
    try testing.expectEqual(@as(u32, 320), w);
    try testing.expectEqual(@as(u32, 240), ht);
    try testing.expectEqual(@as(abi_render_gpu.c.ke_gpu_texture_format, abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM), t.*.format.?(t));
    try frame(t);
    try testing.expectEqual(@as(u32, 0), Fake.started);
}

test "a target destroyed with a capture open discards it" {
    var inner: Fake = undefined;
    const api = inner.init(0);
    const p = abi_gpu_render_target_renderdoc_factory.c.ke_gpu_render_target_renderdoc_params{ .first_frame = 0, .frame_count = 1 };
    const h = try create(&inner.vtable, &p, api);
    const t = h.ref orelse return error.TestUnexpectedResult;

    try testing.expectEqual(@as(abi_asset_resolver.c.ke_gpu_texture_view, 9), try acquired(t));
    h.destroy.?(t);
    try testing.expectEqual(@as(u32, 1), Fake.discarded);
    try heap.expectNoLeaks();
}

test "creation is refused without an inner target, without params, and when RenderDoc is not loaded" {
    var inner: Fake = undefined;
    const api = inner.init(0);
    const p = abi_gpu_render_target_renderdoc_factory.c.ke_gpu_render_target_renderdoc_params{ .first_frame = 0, .frame_count = 1 };

    try testing.expectError(error.InvalidArgument, create(null, &p, api));
    try testing.expectError(error.InvalidArgument, create(&inner.vtable, null, api));

    var h: abi_render_gpu.c.ke_gpu_render_target_handle = undefined;
    try testing.expectError(error.NotFound, R.check(ke_gpu_render_target_renderdoc_create(&inner.vtable, &p, &h)));
    try testing.expect(h.ref == null);
    try heap.expectNoLeaks();
}
