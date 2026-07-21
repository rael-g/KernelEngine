// Tests for the backend-agnostic window core, driven through a fake device.
//
// These replace the gmock-based tests the C++ implementation had: the device
// seam is a Zig vtable now, so the substitute lives here rather than in the C++
// suite, which can only reach the plugin's C ABI.

const std = @import("std");
const testing = std.testing;

const c = @import("c.zig").c;
const device = @import("device.zig");
const core_mod = @import("core.zig");

// -- fake device -------------------------------------------------------------

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

    /// Replayed to the sink on the next pollEvents call.
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
        // The fake is stack-owned by each test, so teardown only records.
        .destroy = struct {
            fn f(ptr: *anyopaque) void {
                from(ptr).destroy_calls += 1;
            }
        }.f,
    };
};

// -- fake input --------------------------------------------------------------

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

fn makeCore(dev: *FakeDevice, input: ?*c.ke_input) *core_mod.Core {
    return core_mod.Core.create(dev.asDevice(), input).?;
}

/// Frees the core without running the device teardown the fake cannot survive
/// (it is stack-owned), while still exercising the shutdown path.
fn destroyCore(core: *core_mod.Core) void {
    core_mod.Core.destroyApi(core.toApi());
}

// -- delegation --------------------------------------------------------------

test "initialize forwards to the device and is idempotent" {
    var dev = FakeDevice{};
    const core = makeCore(&dev, null);
    defer destroyCore(core);

    try testing.expect(core.initialize(.{ .title = "t", .width = 1, .height = 1, .fullscreen = false, .vsync = true }));
    try testing.expect(core.initialize(.{ .title = "t", .width = 1, .height = 1, .fullscreen = false, .vsync = true }));
    try testing.expectEqual(@as(u32, 1), dev.initialize_calls);
}

test "initialize reports failure when the device refuses" {
    var dev = FakeDevice{ .initialize_result = false };
    const core = makeCore(&dev, null);
    defer destroyCore(core);

    try testing.expect(!core.initialize(.{ .title = "t", .width = 1, .height = 1, .fullscreen = false, .vsync = true }));
}

test "should_close reflects the device" {
    var dev = FakeDevice{ .should_close_result = false };
    const core = makeCore(&dev, null);
    defer destroyCore(core);

    const api = core.toApi();
    try testing.expectEqual(@as(c.ke_bool, 0), api.should_close.?(api));
    dev.should_close_result = true;
    try testing.expectEqual(@as(c.ke_bool, 1), api.should_close.?(api));
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

// -- null-self handling ------------------------------------------------------

test "the C ABI slots tolerate a null self" {
    var dev = FakeDevice{};
    const core = makeCore(&dev, null);
    defer destroyCore(core);

    const api = core.toApi();
    try testing.expect(!api.poll_events.?(null, null));
    try testing.expectEqual(@as(c.ke_bool, 1), api.should_close.?(null));
    try testing.expectEqual(@as(?*anyopaque, null), api.get_native_handle.?(null));
    try testing.expect(!api.get_size.?(null, null, null, null));
    try testing.expect(!api.on_shutdown.?(null, null));
    core_mod.Core.destroyApi(null); // must not crash
}

// -- event translation -------------------------------------------------------

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
