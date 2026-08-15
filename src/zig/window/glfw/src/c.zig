
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
