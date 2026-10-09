//! The window backend's state and its vtable slots. `Core` owns a device and borrows an optional
//! input; `create` fills a `ke_window` table whose handle points back at the Core, so each slot
//! recovers its state from the table it is given. The device is started by `initialize`, and the
//! Core remembers that, so a repeated start does not reach the device again.
//!
//! Teardown has two forms. The shutdown slot stops the device and keeps everything, so the window
//! can be started again. `destroyApi` stops the device, destroys it and frees the Core, and is the
//! only place that memory is released.
//!
//! Polling hands the device `handleEvent` as its sink. During the poll it translates key, mouse
//! button, cursor and scroll events into the input's callbacks, and drops every other event and
//! any event whose callback is absent. A slot given a null table reports invalid argument, except
//! the should-close slot, which says the window should close, and the native-handle slot, which
//! returns null.

const std = @import("std");

const c = @import("c.zig").c;
const device = @import("device.zig");
const heap = @import("heap");

/// Reports failures into the error out-parameter, bound to this plugin's C declarations.
const E = @import("kerror").Errors(c);

/// The backend object behind `ke_window`. Created by `create` and freed by `destroyApi`, which
/// also destroys the owned `dev`. `input` is borrowed and may be null; `initialized` is set by
/// `initialize` and cleared by `shutdownInternal`.
pub const Core = struct {
    api: c.ke_window,
    dev: ?device.Device,
    input: ?*c.ke_input,
    initialized: bool,

    /// Returns null when the heap cannot provide the Core. The Core starts uninitialized, and a
    /// null `input` is accepted: events are then dropped.
    pub fn create(dev: device.Device, input: ?*c.ke_input) ?*Core {
        const self = heap.gpa.create(Core) catch return null;
        self.* = .{
            .api = std.mem.zeroes(c.ke_window),
            .dev = dev,
            .input = input,
            .initialized = false,
        };
        self.api.handle = self;
        self.api.on_initialize = onInitialize;
        self.api.on_shutdown = onShutdown;
        self.api.should_close = shouldClose;
        self.api.poll_events = pollEvents;
        self.api.get_size = getSize;
        self.api.get_native_handle = getNativeHandle;
        return self;
    }

    /// Starts the device at most once. A second call returns true without reaching the device. A
    /// refused call leaves the Core uninitialized, so a later call reaches the device again.
    pub fn initialize(self: *Core, config: device.Config) bool {
        const dev = self.dev orelse return false;
        if (self.initialized) return true;
        if (!dev.initialize(config)) return false;
        self.initialized = true;
        return true;
    }

    /// The returned pointer stays valid until `destroyApi` frees the Core.
    pub fn toApi(self: *Core) *c.ke_window {
        return &self.api;
    }

    fn from(self: ?*c.ke_window) ?*Core {
        const s = self orelse return null;
        return @ptrCast(@alignCast(s.handle));
    }

    /// Stops the device but keeps `dev`, so `initialize` can start the same device again.
    fn shutdownInternal(self: *Core) void {
        if (self.dev) |dev| dev.shutdown();
        self.initialized = false;
    }

    /// The owner handle's `destroy` slot, and the factory's rollback when `initialize` fails. The
    /// `ke_window` pointer handed out earlier is dangling once it returns. A null handle does
    /// nothing.
    pub fn destroyApi(self_in: ?*c.ke_window) callconv(.c) void {
        const self = from(self_in) orelse return;
        self.shutdownInternal();
        if (self.dev) |dev| dev.destroy();
        self.dev = null;
        heap.gpa.destroy(self);
    }

    fn onInitialize(self_in: ?*c.ke_window, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
        if (from(self_in) == null) {
            E.fail(out_error, .invalid_argument, "invalid argument", @src());
            return false;
        }
        return true;
    }

    fn onShutdown(self_in: ?*c.ke_window, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
        const self = from(self_in) orelse {
            E.fail(out_error, .invalid_argument, "invalid argument", @src());
            return false;
        };
        self.shutdownInternal();
        return true;
    }

    /// A missing handle or device answers that the window should close.
    fn shouldClose(self_in: ?*c.ke_window) callconv(.c) c.ke_bool {
        const self = from(self_in) orelse return 1;
        const dev = self.dev orelse return 1;
        return if (dev.shouldClose()) 1 else 0;
    }

    fn pollEvents(self_in: ?*c.ke_window, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
        const self = from(self_in) orelse {
            E.fail(out_error, .invalid_argument, "invalid argument", @src());
            return false;
        };
        const dev = self.dev orelse return true;
        dev.pollEvents(.{ .ctx = self, .on_event = handleEvent });
        return true;
    }

    fn getSize(
        self_in: ?*c.ke_window,
        width: [*c]i32,
        height: [*c]i32,
        out_error: [*c][*c]c.ke_error,
    ) callconv(.c) bool {
        const self = from(self_in) orelse {
            E.fail(out_error, .invalid_argument, "invalid argument", @src());
            return false;
        };
        const dev = self.dev orelse return false;
        var w: u32 = 0;
        var h: u32 = 0;
        dev.getSize(&w, &h);
        if (width != null) width.* = @intCast(w);
        if (height != null) height.* = @intCast(h);
        return true;
    }

    fn getNativeHandle(self_in: ?*c.ke_window) callconv(.c) ?*anyopaque {
        const self = from(self_in) orelse return null;
        const dev = self.dev orelse return null;
        return dev.getNativeHandle();
    }

    /// Runs inside the device's poll, once per drained event. Each input callback is optional and
    /// is checked when the event arrives; an event whose callback is absent is dropped.
    fn handleEvent(ctx: *anyopaque, ev: device.Event) void {
        const self: *Core = @ptrCast(@alignCast(ctx));
        const input = self.input orelse return;
        switch (ev.type) {
            .key_down, .key_up => {
                const action: c_int = if (ev.type == .key_down) c.KE_INPUT_ACTION_PRESS else c.KE_INPUT_ACTION_RELEASE;
                if (input.on_key) |f| f(input, @intCast(ev.data.key.key_code), action);
            },
            .mouse_move => {
                if (input.on_mouse_move) |f| f(input, ev.data.mouse_move.x, ev.data.mouse_move.y);
            },
            .mouse_button_down, .mouse_button_up => {
                const action: c_int = if (ev.type == .mouse_button_down) c.KE_INPUT_ACTION_PRESS else c.KE_INPUT_ACTION_RELEASE;
                if (input.on_mouse_button) |f| f(input, @intCast(ev.data.mouse_button.button), action);
            },
            .mouse_scroll => {
                if (input.on_mouse_scroll) |f| f(input, ev.data.mouse_scroll.delta_x, ev.data.mouse_scroll.delta_y);
            },
            else => {},
        }
    }
};
