// ke_window_glfw — the GLFW window plugin's single exported factory. Assembles
// the GLFW device with the backend-agnostic core and hands back the ke_window
// vtable.

const std = @import("std");

// dlopen'd by a foreign (non-Zig) host (the C# runtime) alongside many other
// plugins in one process. std.Thread's default 256 KiB threadlocal signal
// stack blows the small glibc static-TLS surplus once enough accumulate
// (verified: "cannot allocate memory in static TLS block"); the extra crash-
// handler stack trace it buys isn't worth an unloadable plugin.
pub const std_options: std.Options = .{ .signal_stack_size = null };

const c = @import("c.zig").c;

const core_mod = @import("core.zig");
const glfw = @import("glfw_device.zig");
const heap = @import("heap.zig");

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
        // destroyApi tears down the device it owns, so the failure path does
        // not need to unwind the two allocations by hand.
        core_mod.Core.destroyApi(core.toApi());
        E.fail(out_error, .general, "window creation failed", @src());
        return null_handle;
    }

    return .{ .ref = core.toApi(), .destroy = core_mod.Core.destroyApi };
}
