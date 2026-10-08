const std = @import("std");
const builtin = @import("builtin");
const dev_impl = @import("gpu_device_webgpu.zig");
const wgpu = dev_impl.wgpu;
const ke = dev_impl.ke;
const gpa = dev_impl.gpa;

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

const Surface = struct { surface: wgpu.WGPUSurface, display: ?*anyopaque };

fn closeDisplay(display: ?*anyopaque) void {
    if (builtin.os.tag != .linux) return;
    if (display) |d| _ = x11.XCloseDisplay(@ptrCast(d));
}

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

fn fail(out_error: [*c][*c]ke.ke_error, etype: *const ke.ke_error_type, msg: [*c]const u8, src: std.builtin.SourceLocation) void {
    ke.ke_error_set(out_error, etype, msg, src.file, @intCast(src.line), null);
}

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

fn windowSize(t: *WindowTarget, out_error: [*c][*c]ke.ke_error) ?[2]u32 {
    var w: i32 = 0;
    var h: i32 = 0;
    if (!t.window.get_size.?(t.window, &w, &h, out_error)) return null;
    return .{ @intCast(@max(w, 0)), @intCast(@max(h, 0)) };
}

fn releaseFrame(t: *WindowTarget) void {
    if (t.view) |v| wgpu.wgpuTextureViewRelease(v);
    if (t.texture) |tex| wgpu.wgpuTextureRelease(tex);
    t.view = null;
    t.texture = null;
}

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

fn size(self: [*c]ke.ke_gpu_render_target, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
    const t = of(self);
    if (out_w != null) out_w.* = t.width;
    if (out_h != null) out_h.* = t.height;
}

fn format(self: [*c]ke.ke_gpu_render_target) callconv(.c) ke.ke_gpu_texture_format {
    return of(self).format;
}

fn destroy(self: [*c]ke.ke_gpu_render_target) callconv(.c) void {
    const t = of(self);
    releaseFrame(t);
    wgpu.wgpuSurfaceUnconfigure(t.surface);
    wgpu.wgpuSurfaceRelease(t.surface);
    closeDisplay(t.display);
    gpa.destroy(t);
}

const Choice = struct { ke_format: ke.ke_gpu_texture_format, wgpu_format: wgpu.WGPUTextureFormat };

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
