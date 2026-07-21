// Single @cImport for the plugin — separate blocks would produce distinct Zig
// types for the same C struct, so anything crossing between these files would
// stop typechecking.
//
// The native-handle accessors live behind per-platform GLFW_EXPOSE_NATIVE_*
// defines; they must be set before glfw3native.h is pulled in.

const builtin = @import("builtin");

pub const c = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/window/window.h");
    @cInclude("kernel_engine/window/glfw/glfw_window.h");
    @cInclude("kernel_engine/input/input.h");
    @cInclude("GLFW/glfw3.h");
    switch (builtin.os.tag) {
        .windows => @cDefine("GLFW_EXPOSE_NATIVE_WIN32", "1"),
        .linux => @cDefine("GLFW_EXPOSE_NATIVE_X11", "1"),
        else => {},
    }
    @cInclude("GLFW/glfw3native.h");
});
