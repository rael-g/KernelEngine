const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

const c = @cImport({
    @cInclude("kernel_engine/render/gpu/gpu_device.h");
    @cInclude("kernel_engine/render/gpu/gpu_commands.h");
    @cInclude("kernel_engine/render/gpu/gpu_render_target.h");
    @cInclude("kernel_engine/render/texture_target/gpu_render_target_texture_create.h");
});

const heap = @import("heap");
const gpa = heap.gpa;
const E = @import("kerror").Errors(c);

const TextureTarget = struct {
    vtable: c.ke_gpu_render_target,
    device: *c.ke_gpu_device,
    view: c.ke_gpu_texture_view,
    width: u32,
    height: u32,
    format: c.ke_gpu_texture_format,
    acquired: bool,
};

fn of(self: [*c]c.ke_gpu_render_target) *TextureTarget {
    return @ptrCast(@alignCast(self.*.handle));
}

fn acquire(self: [*c]c.ke_gpu_render_target, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_gpu_texture_view {
    const t = of(self);
    if (t.acquired) {
        E.fail(out_error, .invalid_argument, "texture target: a frame is already acquired", @src());
        return c.KE_GPU_INVALID_HANDLE;
    }
    t.acquired = true;
    return t.view;
}

fn present(self: [*c]c.ke_gpu_render_target, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const t = of(self);
    if (!t.acquired) {
        E.fail(out_error, .invalid_argument, "texture target: no frame is acquired", @src());
        return false;
    }
    t.acquired = false;
    return true;
}

fn size(self: [*c]c.ke_gpu_render_target, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
    const t = of(self);
    if (out_w != null) out_w.* = t.width;
    if (out_h != null) out_h.* = t.height;
}

fn format(self: [*c]c.ke_gpu_render_target) callconv(.c) c.ke_gpu_texture_format {
    return of(self).format;
}

fn destroy(self: [*c]c.ke_gpu_render_target) callconv(.c) void {
    const t = of(self);
    t.device.destroy_texture_view.?(t.device, t.view);
    gpa.destroy(t);
}

export fn ke_gpu_render_target_texture_create(
    device: ?*c.ke_gpu_device,
    params: ?*const c.ke_gpu_render_target_texture_params,
    out_error: [*c][*c]c.ke_error,
) c.ke_gpu_render_target_handle {
    const empty: c.ke_gpu_render_target_handle = .{ .ref = null, .destroy = null };
    const dev = device orelse {
        E.fail(out_error, .invalid_argument, "texture target: device is required", @src());
        return empty;
    };
    const p = params orelse {
        E.fail(out_error, .invalid_argument, "texture target: params are required", @src());
        return empty;
    };
    if (p.texture == c.KE_GPU_INVALID_HANDLE or p.format == c.KE_GPU_TEXTURE_FORMAT_INVALID or p.width == 0 or p.height == 0) {
        E.fail(out_error, .invalid_argument, "texture target: the texture, its format and a non-zero size are required", @src());
        return empty;
    }
    const view = dev.create_texture_view.?(dev, p.texture, &c.ke_gpu_texture_view_params{
        .format = p.format,
        .dimension = c.KE_GPU_TEXTURE_DIM_2D,
        .aspect = c.KE_GPU_TEXTURE_ASPECT_COLOR,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 1,
    });
    if (view == c.KE_GPU_INVALID_HANDLE) {
        E.fail(out_error, .invalid_argument, "texture target: the texture has no color view", @src());
        return empty;
    }
    const t = gpa.create(TextureTarget) catch {
        dev.destroy_texture_view.?(dev, view);
        E.fail(out_error, .out_of_memory, "texture target: out of memory", @src());
        return empty;
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
    return .{ .ref = &t.vtable, .destroy = destroy };
}

const testing = std.testing;
const Stubs = @import("stubs").Stubs(c);

fn validParams() c.ke_gpu_render_target_texture_params {
    return .{ .texture = 7, .width = 64, .height = 32, .format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM };
}

test "a texture target hands out one view per frame, reports the texture's size and format, and releases its view" {
    var dev: Stubs.Device = undefined;
    dev.init();
    const p = validParams();
    const h = ke_gpu_render_target_texture_create(dev.api(), &p, null);
    const t = h.ref orelse return error.TestUnexpectedResult;

    var w: u32 = 0;
    var ht: u32 = 0;
    t.*.size.?(t, &w, &ht);
    try testing.expectEqual(@as(u32, 64), w);
    try testing.expectEqual(@as(u32, 32), ht);
    try testing.expectEqual(@as(c.ke_gpu_texture_format, c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM), t.*.format.?(t));

    const first = t.*.acquire.?(t, null);
    try testing.expect(first != c.KE_GPU_INVALID_HANDLE);
    try testing.expect(t.*.present.?(t, null));
    try testing.expectEqual(first, t.*.acquire.?(t, null));
    try testing.expect(t.*.present.?(t, null));

    h.destroy.?(t);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a texture target refuses a second acquire and a present without a frame" {
    var dev: Stubs.Device = undefined;
    dev.init();
    const p = validParams();
    const h = ke_gpu_render_target_texture_create(dev.api(), &p, null);
    const t = h.ref orelse return error.TestUnexpectedResult;
    defer h.destroy.?(t);

    var err: [*c]c.ke_error = null;
    try testing.expect(!t.*.present.?(t, &err));
    try testing.expect(err != null);

    _ = t.*.acquire.?(t, null);
    err = null;
    try testing.expectEqual(@as(c.ke_gpu_texture_view, c.KE_GPU_INVALID_HANDLE), t.*.acquire.?(t, &err));
    try testing.expect(err != null);
}

test "a texture target without a device, params, texture, format or size is refused and leaves nothing behind" {
    var dev: Stubs.Device = undefined;
    dev.init();
    const valid = validParams();
    var cases = [_]c.ke_gpu_render_target_texture_params{ valid, valid, valid, valid };
    cases[0].texture = c.KE_GPU_INVALID_HANDLE;
    cases[1].format = c.KE_GPU_TEXTURE_FORMAT_INVALID;
    cases[2].width = 0;
    cases[3].height = 0;
    for (&cases) |*p| {
        var err: [*c]c.ke_error = null;
        try testing.expect(ke_gpu_render_target_texture_create(dev.api(), p, &err).ref == null);
        try testing.expect(err != null);
    }
    var err: [*c]c.ke_error = null;
    try testing.expect(ke_gpu_render_target_texture_create(null, &valid, &err).ref == null);
    try testing.expect(err != null);
    err = null;
    try testing.expect(ke_gpu_render_target_texture_create(dev.api(), null, &err).ref == null);
    try testing.expect(err != null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}
