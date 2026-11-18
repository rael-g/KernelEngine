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
const abi_settings = @import("abi_settings");
const settings_schema = @import("settings_schema");

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

/// The window's settings: the keys of the window contract, with this implementation's defaults.
const Settings = struct {
    title: [:0]const u8 = "KernelEngine",
    width: u32 = 1280,
    height: u32 = 720,
    fullscreen: bool = false,

    pub const ranges = .{ .width = .{ 1, 16384 }, .height = .{ 1, 16384 } };
};

/// Creates the window and starts it with its settings read once through `Settings`. Fails with
/// invalid argument when the settings or the out-parameter are null or a setting is refused, out
/// of memory when the device or the core cannot be allocated, and general when the core's
/// initialization is refused, leaving the handle zeroed. On success the handle's ref is the core's
/// window table and its destroy is the only way to release the window and its device. The input is
/// handed to the core, which borrows it.
export fn ke_window_glfw_create(
    input: ?*abi_input.c.ke_input,
    settings: ?*abi_settings.c.ke_settings,
    out_window: ?*abi_window.c.ke_window_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_window orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_window.c.ke_window_handle);
    const given = settings orelse {
        log.warn("creating the window failed: no settings", .{});
        return R.code(error.InvalidArgument);
    };
    out.* = create(input, given) catch |err| {
        log.warn("creating the window failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn configOf(settings: *abi_settings.c.ke_settings) R.Error!device.Config {
    const v = try settings_schema.read(Settings, settings);
    return .{ .title = v.title.ptr, .width = v.width, .height = v.height, .fullscreen = v.fullscreen };
}

fn create(input: ?*abi_input.c.ke_input, settings: *abi_settings.c.ke_settings) R.Error!abi_window.c.ke_window_handle {
    const config = try configOf(settings);
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

test "settings that write nothing give a 1280 by 720 window titled KernelEngine" {
    var settings = settings_schema.Fixed.init(&.{});
    const config = try configOf(&settings.api);
    try std.testing.expectEqualStrings("KernelEngine", std.mem.span(config.title));
    try std.testing.expectEqual(@as(u32, 1280), config.width);
    try std.testing.expectEqual(@as(u32, 720), config.height);
    try std.testing.expect(!config.fullscreen);
}

test "a written width replaces the default, and a zero width is refused" {
    var narrow = settings_schema.Fixed.init(&.{.{ .key = "width", .value = .{ .int = 640 } }});
    try std.testing.expectEqual(@as(u32, 640), (try configOf(&narrow.api)).width);
    var zero = settings_schema.Fixed.init(&.{.{ .key = "width", .value = .{ .int = 0 } }});
    try std.testing.expectError(error.InvalidArgument, configOf(&zero.api));
}

test "creating with a zero width fails with invalid argument and leaves the handle zeroed" {
    var zero = settings_schema.Fixed.init(&.{.{ .key = "width", .value = .{ .int = 0 } }});
    var window: abi_window.c.ke_window_handle = undefined;
    try std.testing.expectEqual(R.code(error.InvalidArgument), ke_window_glfw_create(null, &zero.api, &window));
    try std.testing.expectEqual(@as(?*anyopaque, null), @as(?*anyopaque, @ptrCast(window.ref)));
}
