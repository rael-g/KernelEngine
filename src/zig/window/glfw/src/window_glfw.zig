//! The entry of the GLFW window plugin: the exported factory `ke_window_glfw_create`, which builds
//! a window from a GLFW device and starts it.

const std = @import("std");

/// Turns off the signal stack that the standard library would allocate for this library.
pub const std_options: std.Options = .{ .signal_stack_size = null };

pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

const c = @import("c.zig").c;

const core_mod = @import("core.zig");
const glfw = @import("glfw_device.zig");
const heap = @import("heap");

test {
    _ = @import("device.zig");
    _ = @import("core.zig");
}

/// Creates the window and starts it. Reports invalid argument when the params are null, out of
/// memory when the device or the core cannot be allocated, and a general failure when the core's
/// initialization is refused; each returns a zeroed handle with the error set. On success the
/// handle's ref is the core's window table and its destroy is the only way to release the window
/// and its device. The title falls back to "KernelEngine" when absent,
/// and a negative size becomes zero. The input in the params is handed to the core, which
/// borrows it.
export fn ke_window_glfw_create(
    params_in: ?*const c.ke_window_glfw_params,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_window_handle {
    const E = @import("kerror").Errors(c);
    const null_handle = std.mem.zeroes(c.ke_window_handle);

    const params = params_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null_handle;
    };

    const dev = glfw.GlfwDevice.create() orelse {
        E.fail(out_error, .out_of_memory, "device allocation failed", @src());
        return null_handle;
    };

    const core = core_mod.Core.create(dev.asDevice(), params.input) orelse {
        heap.gpa.destroy(dev);
        E.fail(out_error, .out_of_memory, "window state allocation failed", @src());
        return null_handle;
    };

    const config: @import("device.zig").Config = .{
        .title = if (params.title != null) params.title else "KernelEngine",
        .width = @intCast(@max(params.width, 0)),
        .height = @intCast(@max(params.height, 0)),
        .fullscreen = params.fullscreen,
    };

    if (!core.initialize(config)) {
        core_mod.Core.destroyApi(core.toApi());
        E.fail(out_error, .general, "window creation failed", @src());
        return null_handle;
    }

    return .{ .ref = core.toApi(), .destroy = core_mod.Core.destroyApi };
}
