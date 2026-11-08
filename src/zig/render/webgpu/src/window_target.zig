//! The window render target of the webgpu plugin: a `ke_gpu_render_target` whose frames are the
//! images of a window's surface.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_gpu = @import("abi_render_gpu");
const std = @import("std");
const builtin = @import("builtin");
const dev_impl = @import("gpu_device_webgpu.zig");
const wgpu = dev_impl.wgpu;
const abi_gpu_device_webgpu_factory = @import("abi_gpu_device_webgpu_factory");
const abi_render = @import("abi_render");
const abi_result = @import("abi_result");
const abi_window = @import("abi_window");
const gpa = dev_impl.gpa;
const R = @import("result").Result(.{});
const log = std.log.scoped(.gpu_webgpu);

/// The state of one window render target. `ke_gpu_render_target_webgpu_window_create` allocates it
/// from `gpa` and hands out `vtable` as the target, with `handle` pointing back at it; the
/// `destroy` slot frees the frame, the surface and, on Linux, the display. `texture` and `view` are
/// null except between `acquire` and `present`. `width` and `height` are zero until the surface is
/// first configured, and afterwards hold the size it was last configured to. `display` is non-null
/// only on Linux, where it is the display the surface was made on.
const WindowTarget = struct {
    vtable: abi_render_gpu.c.ke_gpu_render_target,
    device: *dev_impl.DeviceState,
    window: *abi_window.c.ke_window,
    surface: wgpu.WGPUSurface,
    display: ?*anyopaque,
    format: abi_render_gpu.c.ke_gpu_texture_format,
    wgpu_format: wgpu.WGPUTextureFormat,
    width: u32,
    height: u32,
    present_mode: wgpu.WGPUPresentMode,
    texture: wgpu.WGPUTexture,
    view: wgpu.WGPUTextureView,
};

const x11 = @import("c");

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
fn createSurface(instance: wgpu.WGPUInstance, window: *abi_window.c.ke_window) ?Surface {
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

fn of(self: [*c]abi_render_gpu.c.ke_gpu_render_target) *WindowTarget {
    return @ptrCast(@alignCast(self.*.handle));
}

/// Logs `msg` and returns the code of `err`.
fn fail(err: R.Error, comptime msg: []const u8) abi_result.c.ke_result {
    log.warn(msg, .{});
    return R.code(err);
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
        .presentMode = t.present_mode,
    };
    wgpu.wgpuSurfaceConfigure(t.surface, &config);
    t.width = width;
    t.height = height;
}

/// Reads the window's client size, with negative values clamped to zero.
fn windowSize(t: *WindowTarget) [2]u32 {
    var w: i32 = 0;
    var h: i32 = 0;
    t.window.get_size.?(t.window, &w, &h);
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

/// Begins a frame and writes its view, which stays valid until `present`. The surface is
/// configured lazily to the window's size, by this call whenever the size changes. An empty window
/// succeeds writing the invalid handle, so the caller skips the frame. A timed-out, outdated or
/// lost texture is not a failure either: the surface is configured again and the invalid handle is
/// written. A failure after the surface produced a texture releases that texture and leaves no
/// frame held.
fn acquire(self: [*c]abi_render_gpu.c.ke_gpu_render_target, out_view: ?*abi_asset_resolver.c.ke_gpu_texture_view) callconv(.c) abi_result.c.ke_result {
    const out = out_view orelse return R.code(error.InvalidArgument);
    out.* = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    const t = of(self);
    if (t.view != null) return fail(error.InvalidArgument, "window target: a frame is already acquired");
    const area = windowSize(t);
    if (area[0] == 0 or area[1] == 0) return R.ok;
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
            return R.ok;
        },
        else => {
            if (st.texture) |tex| wgpu.wgpuTextureRelease(tex);
            return fail(error.NotInitialized, "window target: the surface has no texture to draw into");
        },
    }
    const view = wgpu.wgpuTextureCreateView(st.texture, null) orelse {
        wgpu.wgpuTextureRelease(st.texture);
        return fail(error.NotInitialized, "window target: the surface texture has no view");
    };
    t.texture = st.texture;
    t.view = view;
    out.* = @intFromPtr(view);
    return R.ok;
}

/// Presents the held frame and releases it. The result of the surface's present is discarded, so a
/// failed present is not reported, and the frame is released either way.
fn present(self: [*c]abi_render_gpu.c.ke_gpu_render_target) callconv(.c) abi_result.c.ke_result {
    const t = of(self);
    if (t.view == null) return fail(error.InvalidArgument, "window target: no frame is acquired");
    _ = wgpu.wgpuSurfacePresent(t.surface);
    releaseFrame(t);
    return R.ok;
}

/// Reports the cached `width` and `height` without asking the window. Those fields change only in
/// `configure`.
fn size(self: [*c]abi_render_gpu.c.ke_gpu_render_target, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
    const t = of(self);
    if (out_w != null) out_w.* = t.width;
    if (out_h != null) out_h.* = t.height;
}

/// Reports the format `chooseFormat` picked at creation.
fn format(self: [*c]abi_render_gpu.c.ke_gpu_render_target) callconv(.c) abi_render_gpu.c.ke_gpu_texture_format {
    return of(self).format;
}

/// The function behind the `destroy` slot of the factory's handle. It releases a held frame before
/// the surface it was drawn from, and closes the display last, after the surface made on it is
/// gone.
fn destroy(self: [*c]abi_render_gpu.c.ke_gpu_render_target) callconv(.c) void {
    const t = of(self);
    releaseFrame(t);
    wgpu.wgpuSurfaceUnconfigure(t.surface);
    wgpu.wgpuSurfaceRelease(t.surface);
    closeDisplay(t.display);
    gpa.destroy(t);
}

const Choice = struct { ke_format: abi_render_gpu.c.ke_gpu_texture_format, wgpu_format: wgpu.WGPUTextureFormat };

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
            wgpu.WGPUTextureFormat_BGRA8Unorm => return .{ .ke_format = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM, .wgpu_format = caps.formats[i] },
            wgpu.WGPUTextureFormat_RGBA8Unorm => return .{ .ke_format = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM, .wgpu_format = caps.formats[i] },
            else => {},
        }
    }
    return null;
}

/// The WebGPU present mode for the one asked for, when the surface offers it on this adapter.
fn presentModeOf(surface: wgpu.WGPUSurface, adapter: wgpu.WGPUAdapter, mode: abi_gpu_device_webgpu_factory.c.ke_gpu_present_mode) ?wgpu.WGPUPresentMode {
    const wanted: wgpu.WGPUPresentMode = switch (mode) {
        abi_gpu_device_webgpu_factory.c.KE_GPU_PRESENT_MODE_FIFO => wgpu.WGPUPresentMode_Fifo,
        abi_gpu_device_webgpu_factory.c.KE_GPU_PRESENT_MODE_MAILBOX => wgpu.WGPUPresentMode_Mailbox,
        abi_gpu_device_webgpu_factory.c.KE_GPU_PRESENT_MODE_IMMEDIATE => wgpu.WGPUPresentMode_Immediate,
        else => return null,
    };
    var caps = std.mem.zeroes(wgpu.WGPUSurfaceCapabilities);
    if (wgpu.wgpuSurfaceGetCapabilities(surface, adapter, &caps) != wgpu.WGPUStatus_Success) return null;
    defer wgpu.wgpuSurfaceCapabilitiesFreeMembers(caps);
    for (caps.presentModes[0..caps.presentModeCount]) |offered| {
        if (offered == wanted) return wanted;
    }
    return null;
}

/// The exported factory, applying `config` as given or the defaults of every field when it is null.
/// Every failure leaves the handle zeroed, logging why, and releases the surface and display made
/// so far, so nothing is left allocated. A device is refused unless its `get_default_queue` slot is
/// the function this plugin installs, and a present mode outside `ke_gpu_present_mode` is refused.
export fn ke_gpu_render_target_webgpu_window_create(
    device: [*c]abi_render_gpu.c.ke_gpu_device,
    window: ?*abi_window.c.ke_window,
    config: ?*const abi_gpu_device_webgpu_factory.c.ke_gpu_render_target_webgpu_window_config,
    out_target: ?*abi_render_gpu.c.ke_gpu_render_target_handle,
) abi_result.c.ke_result {
    const out = out_target orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const given = config orelse &abi_gpu_device_webgpu_factory.c.ke_gpu_render_target_webgpu_window_config_defaults;
    if (given.present_mode > abi_gpu_device_webgpu_factory.c.KE_GPU_PRESENT_MODE_IMMEDIATE) {
        return fail(error.InvalidArgument, "window target: the present mode is not a ke_gpu_present_mode");
    }
    if (device == null or device.*.get_default_queue != dev_impl.getDefaultQueue) {
        return fail(error.InvalidArgument, "window target: the device was not created by ke_gpu_device_webgpu_create");
    }
    const win = window orelse {
        return fail(error.InvalidArgument, "window target: window is required");
    };
    const ds = dev_impl.state(device);
    const created = createSurface(ds.instance, win) orelse {
        return fail(error.NotInitialized, "window target: the window has no surface");
    };
    const surface = created.surface;
    const choice = chooseFormat(surface, ds.adapter) orelse {
        wgpu.wgpuSurfaceRelease(surface);
        closeDisplay(created.display);
        return fail(error.NotSupported, "window target: the surface offers no RGBA8 or BGRA8 format on this adapter");
    };
    const present_mode = presentModeOf(surface, ds.adapter, given.present_mode) orelse {
        wgpu.wgpuSurfaceRelease(surface);
        closeDisplay(created.display);
        return fail(error.NotSupported, "window target: the surface does not offer the present mode asked for");
    };
    const t = gpa.create(WindowTarget) catch {
        wgpu.wgpuSurfaceRelease(surface);
        closeDisplay(created.display);
        return fail(error.OutOfMemory, "window target: out of memory");
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
        .present_mode = present_mode,
        .texture = null,
        .view = null,
    };
    const initial = windowSize(t);
    if (initial[0] != 0 and initial[1] != 0) configure(t, initial[0], initial[1]);
    out.* = .{ .ref = &t.vtable, .destroy = destroy };
    return R.ok;
}

/// Frees a target that the factory abandons before configuring its surface. It releases the surface
/// and display and frees the target, without the unconfigure and frame release that `destroy` runs.
fn destroyUnconfigured(t: *WindowTarget) void {
    wgpu.wgpuSurfaceRelease(t.surface);
    closeDisplay(t.display);
    gpa.destroy(t);
}

test "a window target refuses a device it did not come from, a missing window and an unknown present mode" {
    var target: abi_render_gpu.c.ke_gpu_render_target_handle = undefined;
    var foreign = std.mem.zeroes(abi_render_gpu.c.ke_gpu_device);
    try std.testing.expectEqual(R.code(error.InvalidArgument), ke_gpu_render_target_webgpu_window_create(&foreign, null, null, &target));
    try std.testing.expect(target.ref == null);
    try std.testing.expectEqual(R.code(error.InvalidArgument), ke_gpu_render_target_webgpu_window_create(&foreign, null, &.{ .present_mode = 7 }, &target));
    try std.testing.expect(target.ref == null);

    var handle: abi_render_gpu.c.ke_gpu_device_handle = undefined;
    if (dev_impl.ke_gpu_device_webgpu_create(null, null, &handle) != R.ok) return error.SkipZigTest;
    const dev = handle.ref;
    defer handle.destroy.?(dev);
    try std.testing.expectEqual(R.code(error.InvalidArgument), ke_gpu_render_target_webgpu_window_create(dev, null, null, &target));
}
