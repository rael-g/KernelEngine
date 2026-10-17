//! The window backend's state and its `ke_window` slots, written over any device of the platform
//! seam.

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

    /// The `on_initialize` slot. The factory already started the device, so this only checks the
    /// table; a null table reports invalid argument.
    fn onInitialize(self_in: ?*c.ke_window, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
        if (from(self_in) == null) {
            E.fail(out_error, .invalid_argument, "invalid argument", @src());
            return false;
        }
        return true;
    }

    /// The `on_shutdown` slot. Stops the device through `shutdownInternal` and keeps the Core; a
    /// null table reports invalid argument.
    fn onShutdown(self_in: ?*c.ke_window, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
        const self = from(self_in) orelse {
            E.fail(out_error, .invalid_argument, "invalid argument", @src());
            return false;
        };
        self.shutdownInternal();
        return true;
    }

    /// A missing handle or device answers that the window should close.
    fn shouldClose(self_in: ?*c.ke_window) callconv(.c) bool {
        const self = from(self_in) orelse return true;
        const dev = self.dev orelse return true;
        return if (dev.shouldClose()) true else false;
    }

    /// The `poll_events` slot. Drains the device's pending events through `handleEvent` before it
    /// returns. A null table reports invalid argument; a Core without a device succeeds and does
    /// nothing.
    fn pollEvents(self_in: ?*c.ke_window, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
        const self = from(self_in) orelse {
            E.fail(out_error, .invalid_argument, "invalid argument", @src());
            return false;
        };
        const dev = self.dev orelse return true;
        dev.pollEvents(.{ .ctx = self, .on_event = handleEvent });
        return true;
    }

    /// The `get_size` slot. Writes the width and height into each non-null out pointer. A null
    /// table reports invalid argument; a Core without a device returns false with no error set.
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

    /// The `get_native_handle` slot. Null when the table or the device is missing.
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

const testing = std.testing;

const FakeDevice = struct {
    initialize_result: bool = true,
    should_close_result: bool = false,
    size: struct { w: u32, h: u32 } = .{ .w = 640, .h = 480 },
    native_handle: ?*anyopaque = @ptrFromInt(0xBEEF),

    initialize_calls: u32 = 0,
    shutdown_calls: u32 = 0,
    poll_calls: u32 = 0,
    destroy_calls: u32 = 0,
    last_title: ?[*:0]const u8 = null,

    queued: []const device.Event = &.{},

    fn asDevice(self: *FakeDevice) device.Device {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn from(ptr: *anyopaque) *FakeDevice {
        return @ptrCast(@alignCast(ptr));
    }

    const vtable: device.VTable = .{
        .initialize = struct {
            fn f(ptr: *anyopaque, _: device.Config) bool {
                const s = from(ptr);
                s.initialize_calls += 1;
                return s.initialize_result;
            }
        }.f,
        .shutdown = struct {
            fn f(ptr: *anyopaque) void {
                from(ptr).shutdown_calls += 1;
            }
        }.f,
        .poll_events = struct {
            fn f(ptr: *anyopaque, sink: device.EventSink) void {
                const s = from(ptr);
                s.poll_calls += 1;
                for (s.queued) |ev| sink.on_event(sink.ctx, ev);
            }
        }.f,
        .should_close = struct {
            fn f(ptr: *anyopaque) bool {
                return from(ptr).should_close_result;
            }
        }.f,
        .set_title = struct {
            fn f(ptr: *anyopaque, title: [*:0]const u8) void {
                from(ptr).last_title = title;
            }
        }.f,
        .get_size = struct {
            fn f(ptr: *anyopaque, w: *u32, h: *u32) void {
                const s = from(ptr);
                w.* = s.size.w;
                h.* = s.size.h;
            }
        }.f,
        .get_native_handle = struct {
            fn f(ptr: *anyopaque) ?*anyopaque {
                return from(ptr).native_handle;
            }
        }.f,
        .destroy = struct {
            fn f(ptr: *anyopaque) void {
                from(ptr).destroy_calls += 1;
            }
        }.f,
    };
};

const InputSpy = struct {
    var keys: [8]struct { code: i32, action: c_int } = undefined;
    var key_count: usize = 0;
    var moves: [8]struct { x: f32, y: f32 } = undefined;
    var move_count: usize = 0;
    var buttons: [8]struct { button: i32, action: c_int } = undefined;
    var button_count: usize = 0;
    var scrolls: [8]struct { dx: f32, dy: f32 } = undefined;
    var scroll_count: usize = 0;

    fn reset() void {
        key_count = 0;
        move_count = 0;
        button_count = 0;
        scroll_count = 0;
    }

    fn onKey(_: [*c]c.ke_input, code: i32, action: c_int) callconv(.c) void {
        keys[key_count] = .{ .code = code, .action = action };
        key_count += 1;
    }
    fn onMouseMove(_: [*c]c.ke_input, x: f32, y: f32) callconv(.c) void {
        moves[move_count] = .{ .x = x, .y = y };
        move_count += 1;
    }
    fn onMouseButton(_: [*c]c.ke_input, button: i32, action: c_int) callconv(.c) void {
        buttons[button_count] = .{ .button = button, .action = action };
        button_count += 1;
    }
    fn onMouseScroll(_: [*c]c.ke_input, dx: f32, dy: f32) callconv(.c) void {
        scrolls[scroll_count] = .{ .dx = dx, .dy = dy };
        scroll_count += 1;
    }

    fn make() c.ke_input {
        var input = std.mem.zeroes(c.ke_input);
        input.on_key = onKey;
        input.on_mouse_move = onMouseMove;
        input.on_mouse_button = onMouseButton;
        input.on_mouse_scroll = onMouseScroll;
        return input;
    }
};

fn makeCore(dev: *FakeDevice, input: ?*c.ke_input) *Core {
    return Core.create(dev.asDevice(), input).?;
}

fn destroyCore(core: *Core) void {
    Core.destroyApi(core.toApi());
}

test "creating and destroying the window core leaves no block allocated" {
    var dev = FakeDevice{};
    destroyCore(makeCore(&dev, null));
    try heap.expectNoLeaks();
}

test "initialize forwards to the device and is idempotent" {
    var dev = FakeDevice{};
    const core = makeCore(&dev, null);
    defer destroyCore(core);

    try testing.expect(core.initialize(.{ .title = "t", .width = 1, .height = 1, .fullscreen = false }));
    try testing.expect(core.initialize(.{ .title = "t", .width = 1, .height = 1, .fullscreen = false }));
    try testing.expectEqual(@as(u32, 1), dev.initialize_calls);
}

test "initialize reports failure when the device refuses" {
    var dev = FakeDevice{ .initialize_result = false };
    const core = makeCore(&dev, null);
    defer destroyCore(core);

    try testing.expect(!core.initialize(.{ .title = "t", .width = 1, .height = 1, .fullscreen = false }));
}

test "should_close reflects the device" {
    var dev = FakeDevice{ .should_close_result = false };
    const core = makeCore(&dev, null);
    defer destroyCore(core);

    const api = core.toApi();
    try testing.expectEqual(false, api.should_close.?(api));
    dev.should_close_result = true;
    try testing.expectEqual(true, api.should_close.?(api));
}

test "get_size and get_native_handle delegate to the device" {
    var dev = FakeDevice{ .size = .{ .w = 1280, .h = 720 } };
    const core = makeCore(&dev, null);
    defer destroyCore(core);

    const api = core.toApi();
    var w: i32 = 0;
    var h: i32 = 0;
    try testing.expect(api.get_size.?(api, &w, &h, null));
    try testing.expectEqual(@as(i32, 1280), w);
    try testing.expectEqual(@as(i32, 720), h);
    try testing.expectEqual(dev.native_handle, api.get_native_handle.?(api));
}

test "poll_events drives the device" {
    var dev = FakeDevice{};
    const core = makeCore(&dev, null);
    defer destroyCore(core);

    const api = core.toApi();
    try testing.expect(api.poll_events.?(api, null));
    try testing.expectEqual(@as(u32, 1), dev.poll_calls);
}

test "shutdown reaches the device" {
    var dev = FakeDevice{};
    const core = makeCore(&dev, null);
    defer destroyCore(core);

    const api = core.toApi();
    try testing.expect(api.on_shutdown.?(api, null));
    try testing.expect(dev.shutdown_calls >= 1);
}

test "the C ABI slots tolerate a null self" {
    var dev = FakeDevice{};
    const core = makeCore(&dev, null);
    defer destroyCore(core);

    const api = core.toApi();
    try testing.expect(!api.poll_events.?(null, null));
    try testing.expectEqual(true, api.should_close.?(null));
    try testing.expectEqual(@as(?*anyopaque, null), api.get_native_handle.?(null));
    try testing.expect(!api.get_size.?(null, null, null, null));
    try testing.expect(!api.on_shutdown.?(null, null));
    Core.destroyApi(null);
}

test "key events reach ke_input with the right action" {
    InputSpy.reset();
    var input = InputSpy.make();
    var dev = FakeDevice{ .queued = &.{
        .{ .type = .key_down, .data = .{ .key = .{ .key_code = 65, .alt = false, .ctrl = false, .shift = false } } },
        .{ .type = .key_up, .data = .{ .key = .{ .key_code = 66, .alt = false, .ctrl = false, .shift = false } } },
    } };
    const core = makeCore(&dev, &input);
    defer destroyCore(core);

    const api = core.toApi();
    try testing.expect(api.poll_events.?(api, null));

    try testing.expectEqual(@as(usize, 2), InputSpy.key_count);
    try testing.expectEqual(@as(i32, 65), InputSpy.keys[0].code);
    try testing.expectEqual(@as(c_int, 1), InputSpy.keys[0].action);
    try testing.expectEqual(@as(i32, 66), InputSpy.keys[1].code);
    try testing.expectEqual(@as(c_int, 0), InputSpy.keys[1].action);
}

test "mouse move, button and scroll events reach ke_input" {
    InputSpy.reset();
    var input = InputSpy.make();
    var dev = FakeDevice{ .queued = &.{
        .{ .type = .mouse_move, .data = .{ .mouse_move = .{ .x = 12.5, .y = -3.0 } } },
        .{ .type = .mouse_button_down, .data = .{ .mouse_button = .{ .button = 2, .x = 0, .y = 0 } } },
        .{ .type = .mouse_button_up, .data = .{ .mouse_button = .{ .button = 2, .x = 0, .y = 0 } } },
        .{ .type = .mouse_scroll, .data = .{ .mouse_scroll = .{ .delta_x = 1.0, .delta_y = -2.0 } } },
    } };
    const core = makeCore(&dev, &input);
    defer destroyCore(core);

    const api = core.toApi();
    try testing.expect(api.poll_events.?(api, null));

    try testing.expectEqual(@as(usize, 1), InputSpy.move_count);
    try testing.expectEqual(@as(f32, 12.5), InputSpy.moves[0].x);
    try testing.expectEqual(@as(f32, -3.0), InputSpy.moves[0].y);

    try testing.expectEqual(@as(usize, 2), InputSpy.button_count);
    try testing.expectEqual(@as(i32, 2), InputSpy.buttons[0].button);
    try testing.expectEqual(@as(c_int, 1), InputSpy.buttons[0].action);
    try testing.expectEqual(@as(c_int, 0), InputSpy.buttons[1].action);

    try testing.expectEqual(@as(usize, 1), InputSpy.scroll_count);
    try testing.expectEqual(@as(f32, 1.0), InputSpy.scrolls[0].dx);
    try testing.expectEqual(@as(f32, -2.0), InputSpy.scrolls[0].dy);
}

test "events are dropped when no input is attached" {
    InputSpy.reset();
    var dev = FakeDevice{ .queued = &.{
        .{ .type = .key_down, .data = .{ .key = .{ .key_code = 65, .alt = false, .ctrl = false, .shift = false } } },
    } };
    const core = makeCore(&dev, null);
    defer destroyCore(core);

    const api = core.toApi();
    try testing.expect(api.poll_events.?(api, null));
    try testing.expectEqual(@as(usize, 0), InputSpy.key_count);
}

test "resize and close events carry no input translation" {
    InputSpy.reset();
    var input = InputSpy.make();
    var dev = FakeDevice{ .queued = &.{
        .{ .type = .resize, .data = .{ .resize = .{ .width = 100, .height = 50 } } },
        .{ .type = .close },
    } };
    const core = makeCore(&dev, &input);
    defer destroyCore(core);

    const api = core.toApi();
    try testing.expect(api.poll_events.?(api, null));
    try testing.expectEqual(@as(usize, 0), InputSpy.key_count);
    try testing.expectEqual(@as(usize, 0), InputSpy.move_count);
}
