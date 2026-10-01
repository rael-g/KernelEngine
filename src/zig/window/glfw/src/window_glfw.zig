
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

const c = @import("c.zig").c;

const core_mod = @import("core.zig");
const glfw = @import("glfw_device.zig");
const heap = @import("heap");

comptime {
    _ = @import("device.zig");
}

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
        .vsync = true,
    };

    if (!core.initialize(config)) {
        core_mod.Core.destroyApi(core.toApi());
        E.fail(out_error, .general, "window creation failed", @src());
        return null_handle;
    }

    heap.retain();
    return .{ .ref = core.toApi(), .destroy = core_mod.Core.destroyApi };
}
