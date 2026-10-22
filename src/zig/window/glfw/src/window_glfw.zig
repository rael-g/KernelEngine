//! The entry of the GLFW window plugin: the exported factory `ke_window_glfw_create`, which builds
//! a window from a GLFW device and starts it.

const std = @import("std");

/// Turns off the signal stack that the standard library would allocate for this library.
pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_window_glfw").logFn };

pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

const c = @import("c");

const core_mod = @import("core.zig");
const glfw = @import("glfw_device.zig");
const heap = @import("heap");
const R = @import("result").Result(c, .{});
const log = std.log.scoped(.window_glfw);

test {
    _ = @import("device.zig");
    _ = @import("core.zig");
}

/// Creates the window and starts it. Fails with invalid argument when the params or the
/// out-parameter are null, out of memory when the device or the core cannot be allocated, and
/// general when the core's initialization is refused, leaving the handle zeroed. On success the
/// handle's ref is the core's window table and its destroy is the only way to release the window
/// and its device. The title falls back to "KernelEngine" when absent, and a negative size becomes
/// zero. The input in the params is handed to the core, which borrows it.
export fn ke_window_glfw_create(
    params_in: ?*const c.ke_window_glfw_params,
    out_window: ?*c.ke_window_handle,
) callconv(.c) c.ke_result {
    const out = out_window orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(c.ke_window_handle);
    const params = params_in orelse return R.code(error.InvalidArgument);
    out.* = create(params) catch |err| {
        log.warn("creating the window failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn create(params: *const c.ke_window_glfw_params) R.Error!c.ke_window_handle {
    const dev = glfw.GlfwDevice.create() orelse return error.OutOfMemory;

    const core = core_mod.Core.create(dev.asDevice(), params.input) orelse {
        heap.gpa.destroy(dev);
        return error.OutOfMemory;
    };

    const config: @import("device.zig").Config = .{
        .title = if (params.title != null) params.title else "KernelEngine",
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
