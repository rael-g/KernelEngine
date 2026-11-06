//! The entry of the GLFW window plugin: the exported factory `ke_window_glfw_create`, which builds
//! a window from a GLFW device and starts it.

const std = @import("std");

/// Turns off the signal stack that the standard library would allocate for this library.
pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_window_glfw").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const abi_input = @import("abi_input");
const abi_result = @import("abi_result");
const abi_window = @import("abi_window");
const abi_window_glfw_factory = @import("abi_window_glfw_factory");

const core_mod = @import("core.zig");
const device = @import("device.zig");
const glfw = @import("glfw_device.zig");
const heap = @import("heap");
const R = @import("result").Result(.{});
const log = std.log.scoped(.window_glfw);

test {
    _ = @import("device.zig");
    _ = @import("core.zig");
}

const Config = abi_window_glfw_factory.c.ke_window_glfw_config;

/// Creates the window and starts it with `config` applied as given, or with the defaults of every
/// field when it is null. Fails with invalid argument when the out-parameter is null, the title is
/// null or a size is not positive, out of memory when the device or the core cannot be allocated,
/// and general when the core's initialization is refused, leaving the handle zeroed. On success the
/// handle's ref is the core's window table and its destroy is the only way to release the window and
/// its device. The input is handed to the core, which borrows it.
export fn ke_window_glfw_create(
    input: ?*abi_input.c.ke_input,
    config: ?*const Config,
    out_window: ?*abi_window.c.ke_window_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_window orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_window.c.ke_window_handle);
    out.* = create(input, config orelse &.{}) catch |err| {
        log.warn("creating the window failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn settingsOf(given: *const Config) R.Error!device.Config {
    const title = given.title orelse return error.InvalidArgument;
    if (given.width <= 0 or given.height <= 0) return error.InvalidArgument;
    return .{ .title = title, .width = @intCast(given.width), .height = @intCast(given.height), .fullscreen = given.fullscreen };
}

fn create(input: ?*abi_input.c.ke_input, given: *const Config) R.Error!abi_window.c.ke_window_handle {
    const config = try settingsOf(given);
    const dev = glfw.GlfwDevice.create() orelse return error.OutOfMemory;

    const core = core_mod.Core.create(dev.asDevice(), input) orelse {
        heap.gpa.destroy(dev);
        return error.OutOfMemory;
    };

    if (!core.initialize(config)) {
        core_mod.Core.destroyApi(core.toApi());
        return error.General;
    }

    return .{ .ref = core.toApi(), .destroy = core_mod.Core.destroyApi };
}

test "a config left at its defaults gives a 1280 by 720 window titled KernelEngine" {
    const settings = try settingsOf(&.{});
    try std.testing.expectEqualStrings("KernelEngine", std.mem.span(settings.title));
    try std.testing.expectEqual(@as(u32, 1280), settings.width);
    try std.testing.expectEqual(@as(u32, 720), settings.height);
    try std.testing.expect(!settings.fullscreen);
}

test "a given config is applied as given" {
    const settings = try settingsOf(&.{ .title = "Pong", .width = 640, .height = 480, .fullscreen = true });
    try std.testing.expectEqualStrings("Pong", std.mem.span(settings.title));
    try std.testing.expectEqual(@as(u32, 640), settings.width);
    try std.testing.expectEqual(@as(u32, 480), settings.height);
    try std.testing.expect(settings.fullscreen);
}

test "a zero width is refused" {
    try std.testing.expectError(error.InvalidArgument, settingsOf(&.{ .width = 0 }));
}

test "a zero height is refused" {
    try std.testing.expectError(error.InvalidArgument, settingsOf(&.{ .height = 0 }));
}

test "a negative size is refused" {
    try std.testing.expectError(error.InvalidArgument, settingsOf(&.{ .width = -1 }));
    try std.testing.expectError(error.InvalidArgument, settingsOf(&.{ .height = -1 }));
}

test "a null title is refused" {
    try std.testing.expectError(error.InvalidArgument, settingsOf(&.{ .title = null }));
}

test "creating with a zero size fails with invalid argument and leaves the handle zeroed" {
    var window: abi_window.c.ke_window_handle = undefined;
    try std.testing.expectEqual(R.code(error.InvalidArgument), ke_window_glfw_create(null, &.{ .width = 0 }, &window));
    try std.testing.expectEqual(@as(?*anyopaque, null), @as(?*anyopaque, @ptrCast(window.ref)));
}
