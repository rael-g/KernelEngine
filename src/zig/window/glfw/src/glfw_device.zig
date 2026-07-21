// GLFW-backed window device. Owns the GLFW window and translates its callbacks
// into the backend-agnostic Event vocabulary the core consumes.

const std = @import("std");
const builtin = @import("builtin");

const c = @import("c.zig").c;
const device = @import("device.zig");

pub const GlfwDevice = struct {
    window: ?*c.GLFWwindow = null,
    /// Set for the duration of pollEvents; the GLFW callbacks read it back off
    /// the window user pointer, so it must not be live outside that call.
    sink: ?device.EventSink = null,

    pub fn create() ?*GlfwDevice {
        const self: *GlfwDevice = @ptrCast(@alignCast(std.c.malloc(@sizeOf(GlfwDevice)) orelse return null));
        self.* = .{};
        return self;
    }

    pub fn asDevice(self: *GlfwDevice) device.Device {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable: device.VTable = .{
        .initialize = initialize,
        .shutdown = shutdown,
        .poll_events = pollEvents,
        .should_close = shouldClose,
        .set_title = setTitle,
        .get_size = getSize,
        .get_native_handle = getNativeHandle,
        .destroy = destroy,
    };

    fn from(ptr: *anyopaque) *GlfwDevice {
        return @ptrCast(@alignCast(ptr));
    }

    fn initialize(ptr: *anyopaque, config: device.Config) bool {
        const self = from(ptr);
        if (c.glfwInit() == 0) return false;

        // No GL context — the renderer owns the surface.
        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
        const monitor = if (config.fullscreen) c.glfwGetPrimaryMonitor() else null;
        self.window = c.glfwCreateWindow(
            @intCast(config.width),
            @intCast(config.height),
            config.title,
            monitor,
            null,
        ) orelse return false;

        c.glfwSetWindowUserPointer(self.window, self);
        _ = c.glfwSetKeyCallback(self.window, keyCallback);
        _ = c.glfwSetCursorPosCallback(self.window, cursorPosCallback);
        _ = c.glfwSetMouseButtonCallback(self.window, mouseButtonCallback);
        _ = c.glfwSetScrollCallback(self.window, scrollCallback);
        _ = c.glfwSetWindowSizeCallback(self.window, windowSizeCallback);
        _ = c.glfwSetWindowCloseCallback(self.window, windowCloseCallback);
        return true;
    }

    fn shutdown(ptr: *anyopaque) void {
        const self = from(ptr);
        if (self.window) |w| {
            c.glfwDestroyWindow(w);
            self.window = null;
        }
        c.glfwTerminate();
    }

    fn pollEvents(ptr: *anyopaque, sink: device.EventSink) void {
        const self = from(ptr);
        self.sink = sink;
        c.glfwPollEvents();
        self.sink = null;
    }

    fn shouldClose(ptr: *anyopaque) bool {
        const self = from(ptr);
        const w = self.window orelse return true;
        return c.glfwWindowShouldClose(w) != 0;
    }

    fn setTitle(ptr: *anyopaque, title: [*:0]const u8) void {
        const self = from(ptr);
        if (self.window) |w| c.glfwSetWindowTitle(w, title);
    }

    fn getSize(ptr: *anyopaque, width: *u32, height: *u32) void {
        const self = from(ptr);
        const w = self.window orelse return;
        var iw: c_int = 0;
        var ih: c_int = 0;
        c.glfwGetWindowSize(w, &iw, &ih);
        width.* = @intCast(@max(iw, 0));
        height.* = @intCast(@max(ih, 0));
    }

    fn getNativeHandle(ptr: *anyopaque) ?*anyopaque {
        const self = from(ptr);
        const w = self.window orelse return null;
        return switch (builtin.os.tag) {
            .windows => @ptrCast(c.glfwGetWin32Window(w)),
            // An X11 window is an integer id, not a pointer. It rides through
            // the void* slot as an integer-sized value and the surface layer
            // converts it back; handing over the GLFWwindow* instead would be
            // misread as a window id.
            .linux => @ptrFromInt(@as(usize, @intCast(c.glfwGetX11Window(w)))),
            else => @ptrCast(w),
        };
    }

    fn destroy(ptr: *anyopaque) void {
        std.c.free(from(ptr));
    }

    // -- GLFW callbacks ------------------------------------------------------

    fn emit(window: ?*c.GLFWwindow, ev: device.Event) void {
        const self: *GlfwDevice = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window) orelse return));
        const sink = self.sink orelse return;
        sink.on_event(sink.ctx, ev);
    }

    fn keyCallback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
        _ = scancode;
        emit(window, .{
            .type = if (action == c.GLFW_RELEASE) .key_up else .key_down,
            .data = .{ .key = .{
                .key_code = @intCast(@max(key, 0)),
                .alt = (mods & c.GLFW_MOD_ALT) != 0,
                .ctrl = (mods & c.GLFW_MOD_CONTROL) != 0,
                .shift = (mods & c.GLFW_MOD_SHIFT) != 0,
            } },
        });
    }

    fn cursorPosCallback(window: ?*c.GLFWwindow, xpos: f64, ypos: f64) callconv(.c) void {
        emit(window, .{
            .type = .mouse_move,
            .data = .{ .mouse_move = .{ .x = @floatCast(xpos), .y = @floatCast(ypos) } },
        });
    }

    fn mouseButtonCallback(window: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.c) void {
        _ = mods;
        emit(window, .{
            .type = if (action == c.GLFW_RELEASE) .mouse_button_up else .mouse_button_down,
            .data = .{ .mouse_button = .{ .button = @intCast(@max(button, 0)), .x = 0, .y = 0 } },
        });
    }

    fn scrollCallback(window: ?*c.GLFWwindow, xoffset: f64, yoffset: f64) callconv(.c) void {
        emit(window, .{
            .type = .mouse_scroll,
            .data = .{ .mouse_scroll = .{ .delta_x = @floatCast(xoffset), .delta_y = @floatCast(yoffset) } },
        });
    }

    fn windowSizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
        emit(window, .{
            .type = .resize,
            .data = .{ .resize = .{
                .width = @intCast(@max(width, 0)),
                .height = @intCast(@max(height, 0)),
            } },
        });
    }

    fn windowCloseCallback(window: ?*c.GLFWwindow) callconv(.c) void {
        emit(window, .{ .type = .close });
    }
};
