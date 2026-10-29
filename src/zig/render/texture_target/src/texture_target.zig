//! A render target whose frame is a view of a texture the caller owns, so drawing into the target
//! draws into that texture.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_gpu_render_target_texture").logFn };

const abi_gpu_render_target_texture_factory = @import("abi_gpu_render_target_texture_factory");
const abi_render = @import("abi_render");
const abi_result = @import("abi_result");

const heap = @import("heap");
const gpa = heap.gpa;
const R = @import("result").Result(.{});
const log = std.log.scoped(.texture_target);

/// The state behind a texture-target handle, allocated by `ke_gpu_render_target_texture_create`
/// and freed by `destroy`. The `vtable` field is handed out, and its `handle` points back here.
/// The device is borrowed; `view` is owned and released through it. `acquired` is true only
/// between `acquire` and `present`.
const TextureTarget = struct {
    vtable: abi_render.ke_gpu_render_target,
    device: *abi_render.ke_gpu_device,
    view: abi_render.ke_gpu_texture_view,
    width: u32,
    height: u32,
    format: abi_render.ke_gpu_texture_format,
    acquired: bool,
};

fn of(self: [*c]abi_render.ke_gpu_render_target) *TextureTarget {
    return @ptrCast(@alignCast(self.*.handle));
}

/// Opens a frame and writes the view built by `ke_gpu_render_target_texture_create`, the same one
/// every frame. Fails as an invalid argument, writing KE_GPU_INVALID_HANDLE, while a frame is
/// already open, leaving that frame open.
fn acquire(self: [*c]abi_render.ke_gpu_render_target, out_view: [*c]abi_render.ke_gpu_texture_view) callconv(.c) abi_result.ke_result {
    const out = out_view orelse return R.code(error.InvalidArgument);
    out.* = abi_render.KE_GPU_INVALID_HANDLE;
    if (self == null) return R.code(error.InvalidArgument);
    const t = of(self);
    if (t.acquired) {
        log.warn("a frame is already acquired", .{});
        return R.code(error.InvalidArgument);
    }
    t.acquired = true;
    out.* = t.view;
    return R.ok;
}

/// Closes the frame that `acquire` opened. Fails as an invalid argument, leaving the flag clear,
/// when no frame is open. It records and submits nothing; it only clears `acquired`.
fn present(self: [*c]abi_render.ke_gpu_render_target) callconv(.c) abi_result.ke_result {
    if (self == null) return R.code(error.InvalidArgument);
    const t = of(self);
    if (!t.acquired) {
        log.warn("no frame is acquired", .{});
        return R.code(error.InvalidArgument);
    }
    t.acquired = false;
    return R.ok;
}

/// Reports the size copied at creation; a null output is skipped.
fn size(self: [*c]abi_render.ke_gpu_render_target, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
    const t = of(self);
    if (out_w != null) out_w.* = t.width;
    if (out_h != null) out_h.* = t.height;
}

/// Reports the format copied at creation.
fn format(self: [*c]abi_render.ke_gpu_render_target) callconv(.c) abi_render.ke_gpu_texture_format {
    return of(self).format;
}

/// Runs through the handle's `destroy` field, not through the vtable. Releases the view and frees
/// the target, after which the handle's `ref` is dangling.
fn destroy(self: [*c]abi_render.ke_gpu_render_target) callconv(.c) void {
    const t = of(self);
    t.device.destroy_texture_view.?(t.device, t.view);
    gpa.destroy(t);
}

/// Builds the color view of the texture, then allocates the target, so a failed allocation has
/// only the view to undo. Fails as an invalid argument when the device or the params are missing
/// or the texture, the format or either size is unset, with the device's code when it yields no
/// color view, and as out of memory when the allocation fails. A failure leaves the handle zeroed,
/// with no view or target left allocated.
export fn ke_gpu_render_target_texture_create(
    device: ?*abi_render.ke_gpu_device,
    params: ?*const abi_gpu_render_target_texture_factory.ke_gpu_render_target_texture_params,
    out_target: [*c]abi_render.ke_gpu_render_target_handle,
) abi_result.ke_result {
    const out = out_target orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const dev = device orelse return R.code(error.InvalidArgument);
    const p = params orelse return R.code(error.InvalidArgument);
    if (p.texture == abi_render.KE_GPU_INVALID_HANDLE or p.format == abi_render.KE_GPU_TEXTURE_FORMAT_INVALID or p.width == 0 or p.height == 0)
        return R.code(error.InvalidArgument);
    var view: abi_render.ke_gpu_texture_view = abi_render.KE_GPU_INVALID_HANDLE;
    const made = dev.create_texture_view.?(dev, p.texture, &abi_render.ke_gpu_texture_view_params{
        .label = "texture_target.view",
        .format = p.format,
        .dimension = abi_render.KE_GPU_TEXTURE_DIM_2D,
        .aspect = abi_render.KE_GPU_TEXTURE_ASPECT_COLOR,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 1,
    }, &view);
    if (made != R.ok) return made;
    const t = gpa.create(TextureTarget) catch |err| {
        dev.destroy_texture_view.?(dev, view);
        return R.code(err);
    };
    t.* = .{
        .vtable = .{ .handle = t, .acquire = acquire, .present = present, .size = size, .format = format },
        .device = dev,
        .view = view,
        .width = p.width,
        .height = p.height,
        .format = p.format,
        .acquired = false,
    };
    out.* = .{ .ref = &t.vtable, .destroy = destroy };
    return R.ok;
}

const testing = std.testing;
const zsub = @import("zsub");

const DeviceSub = zsub.For(abi_render.ke_gpu_device);

fn substituteDevice(dev: *DeviceSub) !void {
    try dev.init();
    _ = dev.when(.create_texture_view).writesFresh(3);
}

fn validParams() abi_gpu_render_target_texture_factory.ke_gpu_render_target_texture_params {
    return .{ .texture = 7, .width = 64, .height = 32, .format = abi_render.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM };
}

test "a texture target hands out one view per frame, reports the texture's size and format, and releases its view" {
    var dev: DeviceSub = undefined;
    try substituteDevice(&dev);
    defer dev.deinit();
    const p = validParams();
    var h: abi_render.ke_gpu_render_target_handle = undefined;
    try R.check(ke_gpu_render_target_texture_create(dev.api(), &p, &h));
    const t = h.ref orelse return error.TestUnexpectedResult;

    var w: u32 = 0;
    var ht: u32 = 0;
    t.*.size.?(t, &w, &ht);
    try testing.expectEqual(@as(u32, 64), w);
    try testing.expectEqual(@as(u32, 32), ht);
    try testing.expectEqual(@as(abi_render.ke_gpu_texture_format, abi_render.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM), t.*.format.?(t));

    var first: abi_render.ke_gpu_texture_view = undefined;
    try R.check(t.*.acquire.?(t, &first));
    try testing.expect(first != abi_render.KE_GPU_INVALID_HANDLE);
    try R.check(t.*.present.?(t));
    var second: abi_render.ke_gpu_texture_view = undefined;
    try R.check(t.*.acquire.?(t, &second));
    try testing.expectEqual(first, second);
    try R.check(t.*.present.?(t));

    h.destroy.?(t);
    try dev.received(.create_texture_view).times(1);
    try dev.received(.destroy_texture_view).sameAs(dev.received(.create_texture_view));
    try heap.expectNoLeaks();
}

test "a texture target refuses a second acquire and a present without a frame" {
    var dev: DeviceSub = undefined;
    try substituteDevice(&dev);
    defer dev.deinit();
    const p = validParams();
    var h: abi_render.ke_gpu_render_target_handle = undefined;
    try R.check(ke_gpu_render_target_texture_create(dev.api(), &p, &h));
    const t = h.ref orelse return error.TestUnexpectedResult;
    defer h.destroy.?(t);

    try testing.expectError(error.InvalidArgument, R.check(t.*.present.?(t)));

    var view: abi_render.ke_gpu_texture_view = undefined;
    try R.check(t.*.acquire.?(t, &view));
    try testing.expectError(error.InvalidArgument, R.check(t.*.acquire.?(t, &view)));
    try testing.expectEqual(@as(abi_render.ke_gpu_texture_view, abi_render.KE_GPU_INVALID_HANDLE), view);
}

test "a texture target without a device, params, texture, format or size is refused and leaves nothing behind" {
    var dev: DeviceSub = undefined;
    try substituteDevice(&dev);
    defer dev.deinit();
    const valid = validParams();
    var cases = [_]abi_gpu_render_target_texture_factory.ke_gpu_render_target_texture_params{ valid, valid, valid, valid };
    cases[0].texture = abi_render.KE_GPU_INVALID_HANDLE;
    cases[1].format = abi_render.KE_GPU_TEXTURE_FORMAT_INVALID;
    cases[2].width = 0;
    cases[3].height = 0;
    var h: abi_render.ke_gpu_render_target_handle = undefined;
    for (&cases) |*p| {
        try testing.expectError(error.InvalidArgument, R.check(ke_gpu_render_target_texture_create(dev.api(), p, &h)));
        try testing.expect(h.ref == null);
    }
    try testing.expectError(error.InvalidArgument, R.check(ke_gpu_render_target_texture_create(null, &valid, &h)));
    try testing.expectError(error.InvalidArgument, R.check(ke_gpu_render_target_texture_create(dev.api(), null, &h)));
    try dev.received(.destroy_texture_view).sameAs(dev.received(.create_texture_view));
    try heap.expectNoLeaks();
}
