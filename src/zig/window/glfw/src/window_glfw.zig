//! The entry of the GLFW window plugin: the exported factory `ke_window_glfw_create`, which builds
//! a window from a GLFW device and starts it.

const std = @import("std");

/// Turns off the signal stack that the standard library would allocate for this library.
pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_window_glfw").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const abi_input = @import("abi_input");
const abi_configuration = @import("abi_configuration");
const abi_result = @import("abi_result");
const abi_window = @import("abi_window");
const abi_window_glfw_factory = @import("abi_window_glfw_factory");

const core_mod = @import("core.zig");
const glfw = @import("glfw_device.zig");
const heap = @import("heap");
const R = @import("result").Result(.{});
const log = std.log.scoped(.window_glfw);

test {
    _ = @import("device.zig");
    _ = @import("core.zig");
}

const Config = abi_window_glfw_factory.c.ke_window_glfw_config;

const default_config: Config = .{ .title = "KernelEngine", .width = 1280, .height = 720, .fullscreen = false };

const config_fields = [_]abi_configuration.c.ke_config_field{
    .{ .key = "title", .type = abi_configuration.c.KE_CONFIG_STRING, .offset = @offsetOf(Config, "title"), .size = @sizeOf([*c]const u8), .default_value = .{ .s = "KernelEngine" } },
    .{ .key = "width", .type = abi_configuration.c.KE_CONFIG_INT, .offset = @offsetOf(Config, "width"), .size = 4, .default_value = .{ .i = 1280 } },
    .{ .key = "height", .type = abi_configuration.c.KE_CONFIG_INT, .offset = @offsetOf(Config, "height"), .size = 4, .default_value = .{ .i = 720 } },
    .{ .key = "fullscreen", .type = abi_configuration.c.KE_CONFIG_BOOL, .offset = @offsetOf(Config, "fullscreen"), .size = 1, .default_value = .{ .b = false } },
};

/// Creates the window and starts it. The settings are the defaults, then what the store holds, then
/// each non-zero field of `config`. Fails with invalid argument when the out-parameter is null, out
/// of memory when the device or the core cannot be allocated, and general when the core's
/// initialization is refused, leaving the handle zeroed. On success the handle's ref is the core's
/// window table and its destroy is the only way to release the window and its device. A negative
/// size becomes zero. The input is handed to the core, which borrows it.
export fn ke_window_glfw_create(
    input: ?*abi_input.c.ke_input,
    configuration: ?*abi_configuration.c.ke_configuration,
    config: ?*const Config,
    out_window: ?*abi_window.c.ke_window_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_window orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_window.c.ke_window_handle);
    var settings = default_config;
    if (configuration) |store| {
        const result = store.fill.?(store, "runtime.window", &config_fields, config_fields.len, &settings);
        if (result != abi_result.c.KE_OK) return result;
    }
    if (config) |given| {
        if (given.title != null) settings.title = given.title;
        if (given.width != 0) settings.width = given.width;
        if (given.height != 0) settings.height = given.height;
        if (given.fullscreen) settings.fullscreen = true;
    }
    out.* = create(input, &settings) catch |err| {
        log.warn("creating the window failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn create(input: ?*abi_input.c.ke_input, params: *const Config) R.Error!abi_window.c.ke_window_handle {
    const dev = glfw.GlfwDevice.create() orelse return error.OutOfMemory;

    const core = core_mod.Core.create(dev.asDevice(), input) orelse {
        heap.gpa.destroy(dev);
        return error.OutOfMemory;
    };

    const config: @import("device.zig").Config = .{
        .title = params.title orelse "KernelEngine",
        .width = @intCast(@max(params.width, 0)),
        .height = @intCast(@max(params.height, 0)),
        .fullscreen = params.fullscreen,
    };

    if (!core.initialize(config)) {
        core_mod.Core.destroyApi(core.toApi());
        return error.General;
    }

    return .{ .ref = core.toApi(), .destroy = core_mod.Core.destroyApi };
}
