//! The window render target of the webgpu plugin: a `ke_gpu_render_target` whose frames are the
//! images of a window's surface. The factory refuses a missing window and a device this plugin did
//! not create, makes the surface from the window's native handle with `createSurface`, picks a
//! format with `chooseFormat`, and allocates a `WindowTarget`. Each failing step releases what the
//! earlier ones made.
//!
//! A frame is held between `acquire` and `present`, as the texture and view of the target. The
//! surface is configured lazily to the window's size: at creation when the window is not empty, and
//! afterwards by `acquire` whenever the size changes or the surface reports a stale texture. An
//! empty window or a stale texture yields the invalid handle without an error, so the caller skips
//! the frame; anything else that goes wrong is an error and leaves no frame held. `destroy`
//! releases the frame, the surface and, on Linux, the display the surface was made on.

const std = @import("std");
const builtin = @import("builtin");
const dev_impl = @import("gpu_device_webgpu.zig");
const wgpu = dev_impl.wgpu;
const ke = dev_impl.ke;
const gpa = dev_impl.gpa;

/// The state of one window render target. `ke_gpu_render_target_webgpu_window_create` allocates
/// it from `gpa` and hands out `vtable` as the target, with `handle` pointing back at it; the
/// `destroy` slot frees it. `texture` and `view` are null except between `acquire` and `present`.
/// `width` and `height` are zero until the surface is first configured, and afterwards hold the
/// size it was last configured to. `display` is non-null only on Linux, where it is the display
/// the surface was made on.
const WindowTarget = struct {
    vtable: ke.ke_gpu_render_target,
    device: *dev_impl.DeviceState,
    window: *ke.ke_window,
    surface: wgpu.WGPUSurface,
    display: ?*anyopaque,
    format: ke.ke_gpu_texture_format,
    wgpu_format: wgpu.WGPUTextureFormat,
    width: u32,
    height: u32,
    texture: wgpu.WGPUTexture,
    view: wgpu.WGPUTextureView,
};

const x11 = if (builtin.os.tag == .linux) @cImport(@cInclude("X11/Xlib.h")) else struct {};

/// What `createSurface` returns: the surface and, on Linux, the display opened to create it. Once
/// the surface is released, the display is closed with `closeDisplay`.
const Surface = struct { surface: wgpu.WGPUSurface, display: ?*anyopaque };

fn closeDisplay(display: ?*anyopaque) void {
    if (builtin.os.tag != .linux) return;
    if (display) |d| _ = x11.XCloseDisplay(@ptrCast(d));
}

/// Sets no error itself: a null return means the window has no native handle, the instance refused
/// the surface, or the operating system is none of Windows, Linux or macOS, and the caller reports
/// it. On Linux a display opened here is closed when the surface cannot be made, and otherwise
/// travels in the returned `Surface` for the caller to close.
fn createSurface(instance: wgpu.WGPUInstance, window: *ke.ke_window) ?Surface {
    const native = window.get_native_handle.?(window) orelse return null;
    switch (builtin.os.tag) {
        .windows => {
            const GetModuleHandleW = @extern(*const fn (?[*:0]const u16) callconv(.winapi) ?std.os.windows.HMODULE, .{ .name = "GetModuleHandleW" });
            const src = wgpu.WGPUSurfaceSourceWindowsHWND{
                .chain = .{ .next = null, .sType = wgpu.WGPUSType_SurfaceSourceWindowsHWND },
                .hinstance = GetModuleHandleW(null),
                .hwnd = native,
            };
            const desc = wgpu.WGPUSurfaceDescriptor{ .nextInChain = @ptrCast(&src), .label = .{ .data = null, .length = 0 } };
            const surface = wgpu.wgpuInstanceCreateSurface(instance, &desc) orelse return null;
            return .{ .surface = surface, .display = null };
        },
        .linux => {
            const display = x11.XOpenDisplay(null) orelse return null;
            const src = wgpu.WGPUSurfaceSourceXlibWindow{
                .chain = .{ .next = null, .sType = wgpu.WGPUSType_SurfaceSourceXlibWindow },
                .display = display,
                .window = @intFromPtr(native),
            };
            const desc = wgpu.WGPUSurfaceDescriptor{ .nextInChain = @ptrCast(&src), .label = .{ .data = null, .length = 0 } };
            const surface = wgpu.wgpuInstanceCreateSurface(instance, &desc) orelse {
                _ = x11.XCloseDisplay(display);
                return null;
            };
            return .{ .surface = surface, .display = display };
        },
        .macos => {
            const src = wgpu.WGPUSurfaceSourceMetalLayer{
                .chain = .{ .next = null, .sType = wgpu.WGPUSType_SurfaceSourceMetalLayer },
                .layer = native,
            };
            const desc = wgpu.WGPUSurfaceDescriptor{ .nextInChain = @ptrCast(&src), .label = .{ .data = null, .length = 0 } };
            const surface = wgpu.wgpuInstanceCreateSurface(instance, &desc) orelse return null;
            return .{ .surface = surface, .display = null };
        },
        else => return null,
    }
}

fn of(self: [*c]ke.ke_gpu_render_target) *WindowTarget {
    return @ptrCast(@alignCast(self.*.handle));
}

/// Records the error at the source location the caller passes, so it names the failing line of the
/// caller rather than this function. Returning the failure sentinel is left to the caller.
fn fail(out_error: [*c][*c]ke.ke_error, etype: *const ke.ke_error_type, msg: [*c]const u8, src: std.builtin.SourceLocation) void {
    ke.ke_error_set(out_error, etype, msg, src.file, @intCast(src.line), null);
}

/// Called by the factory for a non-empty window, by `acquire` when the window size differs from the
/// cached one, and by `acquire` again after a texture is refused. Afterwards `width` and `height`
/// hold the configured size, which `size` reports.
fn configure(t: *WindowTarget, width: u32, height: u32) void {
    const config = wgpu.WGPUSurfaceConfiguration{
        .nextInChain = null,
        .device = t.device.device,
        .format = t.wgpu_format,
        .usage = wgpu.WGPUTextureUsage_RenderAttachment,
        .viewFormatCount = 0,
        .viewFormats = null,
        .alphaMode = wgpu.WGPUCompositeAlphaMode_Auto,
        .width = width,
        .height = height,
        .presentMode = wgpu.WGPUPresentMode_Fifo,
    };
    wgpu.wgpuSurfaceConfigure(t.surface, &config);
    t.width = width;
    t.height = height;
}

/// Reads the window's client size, with negative values clamped to zero. When the window cannot
/// report it, returns null and leaves in the out error parameter the error its `get_size` set.
fn windowSize(t: *WindowTarget, out_error: [*c][*c]ke.ke_error) ?[2]u32 {
    var w: i32 = 0;
    var h: i32 = 0;
    if (!t.window.get_size.?(t.window, &w, &h, out_error)) return null;
    return .{ @intCast(@max(w, 0)), @intCast(@max(h, 0)) };
}

/// Releases the held frame, the view before the texture it was created from, and clears both
/// fields. With no frame held it does nothing. `present` and `destroy` are the callers.
fn releaseFrame(t: *WindowTarget) void {
    if (t.view) |v| wgpu.wgpuTextureViewRelease(v);
    if (t.texture) |tex| wgpu.wgpuTextureRelease(tex);
    t.view = null;
    t.texture = null;
}

/// Begins a frame and returns its view, which stays valid until `present`. A timed-out, outdated or
/// lost texture is not an error: the surface is configured again and the invalid handle is returned
/// with no error set. A failure after the surface produced a texture releases that texture and
/// leaves no frame held.
fn acquire(self: [*c]ke.ke_gpu_render_target, out_error: [*c][*c]ke.ke_error) callconv(.c) ke.ke_gpu_texture_view {
    const t = of(self);
    if (t.view != null) {
        fail(out_error, &ke.KE_ERROR_INVALID_ARGUMENT, "window target: a frame is already acquired", @src());
        return ke.KE_GPU_INVALID_HANDLE;
    }
    const area = windowSize(t, out_error) orelse return ke.KE_GPU_INVALID_HANDLE;
    if (area[0] == 0 or area[1] == 0) return ke.KE_GPU_INVALID_HANDLE;
    if (area[0] != t.width or area[1] != t.height) configure(t, area[0], area[1]);

    var st = std.mem.zeroes(wgpu.WGPUSurfaceTexture);
    wgpu.wgpuSurfaceGetCurrentTexture(t.surface, &st);
    switch (st.status) {
        wgpu.WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal,
        wgpu.WGPUSurfaceGetCurrentTextureStatus_SuccessSuboptimal,
        => {},
        wgpu.WGPUSurfaceGetCurrentTextureStatus_Timeout,
        wgpu.WGPUSurfaceGetCurrentTextureStatus_Outdated,
        wgpu.WGPUSurfaceGetCurrentTextureStatus_Lost,
        => {
            if (st.texture) |tex| wgpu.wgpuTextureRelease(tex);
            configure(t, area[0], area[1]);
            return ke.KE_GPU_INVALID_HANDLE;
        },
        else => {
            if (st.texture) |tex| wgpu.wgpuTextureRelease(tex);
            fail(out_error, &ke.KE_ERROR_NOT_INITIALIZED, "window target: the surface has no texture to draw into", @src());
            return ke.KE_GPU_INVALID_HANDLE;
        },
    }
    const view = wgpu.wgpuTextureCreateView(st.texture, null) orelse {
        wgpu.wgpuTextureRelease(st.texture);
        fail(out_error, &ke.KE_ERROR_NOT_INITIALIZED, "window target: the surface texture has no view", @src());
        return ke.KE_GPU_INVALID_HANDLE;
    };
    t.texture = st.texture;
    t.view = view;
    return @intFromPtr(view);
}

/// Presents the held frame and releases it. The result of the surface's present is discarded, so a
/// failed present is not reported, and the frame is released either way.
fn present(self: [*c]ke.ke_gpu_render_target, out_error: [*c][*c]ke.ke_error) callconv(.c) bool {
    const t = of(self);
    if (t.view == null) {
        fail(out_error, &ke.KE_ERROR_INVALID_ARGUMENT, "window target: no frame is acquired", @src());
        return false;
    }
    _ = wgpu.wgpuSurfacePresent(t.surface);
    releaseFrame(t);
    return true;
}

/// Reports the cached `width` and `height` without asking the window. Those fields change only in
/// `configure`.
fn size(self: [*c]ke.ke_gpu_render_target, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
    const t = of(self);
    if (out_w != null) out_w.* = t.width;
    if (out_h != null) out_h.* = t.height;
}

fn format(self: [*c]ke.ke_gpu_render_target) callconv(.c) ke.ke_gpu_texture_format {
    return of(self).format;
}

/// The function behind the `destroy` slot of the factory's handle. It releases a held frame before
/// the surface it was drawn from, and closes the display last, after the surface made on it is
/// gone.
fn destroy(self: [*c]ke.ke_gpu_render_target) callconv(.c) void {
    const t = of(self);
    releaseFrame(t);
    wgpu.wgpuSurfaceUnconfigure(t.surface);
    wgpu.wgpuSurfaceRelease(t.surface);
    closeDisplay(t.display);
    gpa.destroy(t);
}

const Choice = struct { ke_format: ke.ke_gpu_texture_format, wgpu_format: wgpu.WGPUTextureFormat };

/// Returns the first format in the surface's listing that is BGRA8 or RGBA8, so the order the
/// driver lists them decides between the two. Returns null when the capabilities cannot be read
/// or neither format is listed. The capabilities are freed before it returns.
fn chooseFormat(surface: wgpu.WGPUSurface, adapter: wgpu.WGPUAdapter) ?Choice {
    var caps = std.mem.zeroes(wgpu.WGPUSurfaceCapabilities);
    if (wgpu.wgpuSurfaceGetCapabilities(surface, adapter, &caps) != wgpu.WGPUStatus_Success) return null;
    defer wgpu.wgpuSurfaceCapabilitiesFreeMembers(caps);
    var i: usize = 0;
    while (i < caps.formatCount) : (i += 1) {
        switch (caps.formats[i]) {
            wgpu.WGPUTextureFormat_BGRA8Unorm => return .{ .ke_format = ke.KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM, .wgpu_format = caps.formats[i] },
            wgpu.WGPUTextureFormat_RGBA8Unorm => return .{ .ke_format = ke.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM, .wgpu_format = caps.formats[i] },
            else => {},
        }
    }
    return null;
}

/// The exported factory. Every failure returns the empty handle with the error set, and releases
/// the surface and display made so far, so nothing is left allocated. A device is refused unless
/// its `get_default_queue` slot is the function this plugin installs.
export fn ke_gpu_render_target_webgpu_window_create(
    device: [*c]ke.ke_gpu_device,
    window: ?*ke.ke_window,
    out_error: [*c][*c]ke.ke_error,
) ke.ke_gpu_render_target_handle {
    const empty: ke.ke_gpu_render_target_handle = .{ .ref = null, .destroy = null };
    if (device == null or device.*.get_default_queue != dev_impl.getDefaultQueue) {
        fail(out_error, &ke.KE_ERROR_INVALID_ARGUMENT, "window target: the device was not created by ke_gpu_device_webgpu_create", @src());
        return empty;
    }
    const win = window orelse {
        fail(out_error, &ke.KE_ERROR_INVALID_ARGUMENT, "window target: window is required", @src());
        return empty;
    };
    const ds = dev_impl.state(device);
    const created = createSurface(ds.instance, win) orelse {
        fail(out_error, &ke.KE_ERROR_NOT_INITIALIZED, "window target: the window has no surface", @src());
        return empty;
    };
    const surface = created.surface;
    const choice = chooseFormat(surface, ds.adapter) orelse {
        wgpu.wgpuSurfaceRelease(surface);
        closeDisplay(created.display);
        fail(out_error, &ke.KE_ERROR_NOT_SUPPORTED, "window target: the surface offers no RGBA8 or BGRA8 format on this adapter", @src());
        return empty;
    };
    const t = gpa.create(WindowTarget) catch {
        wgpu.wgpuSurfaceRelease(surface);
        closeDisplay(created.display);
        fail(out_error, &ke.KE_ERROR_OUT_OF_MEMORY, "window target: out of memory", @src());
        return empty;
    };
    t.* = .{
        .vtable = .{ .handle = t, .acquire = acquire, .present = present, .size = size, .format = format },
        .device = ds,
        .window = win,
        .surface = surface,
        .display = created.display,
        .format = choice.ke_format,
        .wgpu_format = choice.wgpu_format,
        .width = 0,
        .height = 0,
        .texture = null,
        .view = null,
    };
    const initial = windowSize(t, out_error) orelse {
        destroyUnconfigured(t);
        return empty;
    };
    if (initial[0] != 0 and initial[1] != 0) configure(t, initial[0], initial[1]);
    return .{ .ref = &t.vtable, .destroy = destroy };
}

/// Frees a target that the factory abandons before configuring its surface. It releases the surface
/// and display and frees the target, without the unconfigure and frame release that `destroy` runs.
fn destroyUnconfigured(t: *WindowTarget) void {
    wgpu.wgpuSurfaceRelease(t.surface);
    closeDisplay(t.display);
    gpa.destroy(t);
}

test "a window target refuses a device it did not come from and a missing window" {
    var foreign = std.mem.zeroes(ke.ke_gpu_device);
    var err: [*c]ke.ke_error = null;
    try std.testing.expect(ke_gpu_render_target_webgpu_window_create(&foreign, null, &err).ref == null);
    try std.testing.expect(err != null);

    const handle = dev_impl.ke_gpu_device_webgpu_create(null, null);
    const dev = handle.ref orelse return error.SkipZigTest;
    defer handle.destroy.?(dev);
    var missing: [*c]ke.ke_error = null;
    try std.testing.expect(ke_gpu_render_target_webgpu_window_create(dev, null, &missing).ref == null);
    try std.testing.expect(missing != null);
}
