const std = @import("std");

// This .so is dlopen'd by a foreign, non-Zig host alongside many sibling
// plugins in one process. std.Thread's default 256 KiB threadlocal signal
// stack exceeds glibc's small static-TLS surplus once enough plugins
// accumulate, aborting with "cannot allocate memory in static TLS block".
pub const std_options: std.Options = .{ .signal_stack_size = null };

const gpa = std.heap.c_allocator;

const c = @cImport({
    @cInclude("kernel_engine/input/input.h");
});

// Zig-native error translation at the C-ABI seam (no ke_common link).
const E = @import("kerror").Errors(c);

const MAX_KEYS = 512;
const EVENT_CAPACITY = 512;

const State = struct {
    keys_down: [MAX_KEYS]bool,
    keys_pressed: [MAX_KEYS]bool,
    keys_released: [MAX_KEYS]bool,

    mouse_x: f32,
    mouse_y: f32,
    mouse_dx: f32,
    mouse_dy: f32,
    scroll_dx: f32,
    scroll_dy: f32,
    mouse_buttons_down: u32,
    mouse_buttons_pressed: u32,
    mouse_buttons_released: u32,

    // Fixed-capacity, single-producer/single-consumer (ke.main) event queue.
    // Overflow is silently dropped — game devs polling via is_key_down still
    // see correct state. Capacity sized for ~1ms of furious input at 1000Hz.
    events: [EVENT_CAPACITY]c.ke_input_event,
    event_count: u32,
    event_overflow: bool,
};

fn stateOf(self: *c.ke_input) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn pushEvent(s: *State, kind: c.ke_input_event_kind, code: i32, x: f32, y: f32) void {
    if (s.event_count >= EVENT_CAPACITY) {
        s.event_overflow = true;
        return;
    }
    const e = &s.events[s.event_count];
    s.event_count += 1;
    e.kind = kind;
    e.code = code;
    e.x = x;
    e.y = y;
}

fn inputUpdate(self: ?*c.ke_input, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const api = self orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    const s = stateOf(api);

    @memset(&s.keys_pressed, false);
    @memset(&s.keys_released, false);
    s.mouse_dx = 0;
    s.mouse_dy = 0;
    s.scroll_dx = 0;
    s.scroll_dy = 0;
    s.mouse_buttons_pressed = 0;
    s.mouse_buttons_released = 0;

    // Events are produced during PollEvents (after update()) and drained by the
    // framework on the same tick; update() clears any stragglers.
    s.event_count = 0;
    s.event_overflow = false;
    return true;
}

fn inputOnKey(self: ?*c.ke_input, key: i32, action: i32) callconv(.c) void {
    const api = self orelse return;
    if (key < 0 or key >= MAX_KEYS) return;
    const s = stateOf(api);
    const k: usize = @intCast(key);
    if (action == 1) {
        if (!s.keys_down[k]) s.keys_pressed[k] = true;
        s.keys_down[k] = true;
        pushEvent(s, c.KE_INPUT_EVENT_KEY_DOWN, key, 0, 0);
    } else if (action == 0) {
        s.keys_released[k] = true;
        s.keys_down[k] = false;
        pushEvent(s, c.KE_INPUT_EVENT_KEY_UP, key, 0, 0);
    }
}

fn inputOnMouseMove(self: ?*c.ke_input, x: f32, y: f32) callconv(.c) void {
    const api = self orelse return;
    const s = stateOf(api);
    s.mouse_dx += (x - s.mouse_x);
    s.mouse_dy += (y - s.mouse_y);
    s.mouse_x = x;
    s.mouse_y = y;
    // No event push: cursor position is continuous state, read via snapshot.
}

fn inputOnMouseButton(self: ?*c.ke_input, button: i32, action: i32) callconv(.c) void {
    const api = self orelse return;
    if (button < 0 or button >= 32) return;
    const s = stateOf(api);
    const mask = @as(u32, 1) << @intCast(button);
    if (action == 1) {
        if ((s.mouse_buttons_down & mask) == 0) s.mouse_buttons_pressed |= mask;
        s.mouse_buttons_down |= mask;
        pushEvent(s, c.KE_INPUT_EVENT_MOUSE_BUTTON_DOWN, button, 0, 0);
    } else if (action == 0) {
        s.mouse_buttons_released |= mask;
        s.mouse_buttons_down &= ~mask;
        pushEvent(s, c.KE_INPUT_EVENT_MOUSE_BUTTON_UP, button, 0, 0);
    }
}

fn inputOnMouseScroll(self: ?*c.ke_input, dx: f32, dy: f32) callconv(.c) void {
    const api = self orelse return;
    const s = stateOf(api);
    s.scroll_dx += dx;
    s.scroll_dy += dy;
    pushEvent(s, c.KE_INPUT_EVENT_MOUSE_SCROLL, 0, dx, dy);
}

fn inputDrainEvents(self: ?*c.ke_input, out_buf: [*c]c.ke_input_event, capacity: u32) callconv(.c) u32 {
    const api = self orelse return 0;
    if (out_buf == null or capacity == 0) return 0;
    const s = stateOf(api);
    const n = @min(s.event_count, capacity);
    if (n > 0) @memcpy(out_buf[0..n], s.events[0..n]);
    s.event_count = 0;
    s.event_overflow = false;
    return n;
}

fn inputIsKeyPressed(self: ?*c.ke_input, key: i32) callconv(.c) c.ke_bool {
    const api = self orelse return 0;
    if (key < 0 or key >= MAX_KEYS) return 0;
    return @intFromBool(stateOf(api).keys_pressed[@intCast(key)]);
}

fn inputIsKeyReleased(self: ?*c.ke_input, key: i32) callconv(.c) c.ke_bool {
    const api = self orelse return 0;
    if (key < 0 or key >= MAX_KEYS) return 0;
    return @intFromBool(stateOf(api).keys_released[@intCast(key)]);
}

fn inputIsKeyDown(self: ?*c.ke_input, key: i32) callconv(.c) c.ke_bool {
    const api = self orelse return 0;
    if (key < 0 or key >= MAX_KEYS) return 0;
    return @intFromBool(stateOf(api).keys_down[@intCast(key)]);
}

fn inputGetSnapshot(self: ?*c.ke_input, out: [*c]c.ke_input_snapshot) callconv(.c) void {
    const api = self orelse return;
    if (out == null) return;
    const s = stateOf(api);
    const o: *c.ke_input_snapshot = @ptrCast(out);
    o.* = std.mem.zeroes(c.ke_input_snapshot);

    for (0..MAX_KEYS) |i| {
        const word = i / 64;
        const bit = @as(u64, 1) << @intCast(i % 64);
        if (s.keys_down[i]) o.keys_down[word] |= bit;
        if (s.keys_pressed[i]) o.keys_pressed[word] |= bit;
        if (s.keys_released[i]) o.keys_released[word] |= bit;
    }

    o.mouse_x = s.mouse_x;
    o.mouse_y = s.mouse_y;
    o.mouse_dx = s.mouse_dx;
    o.mouse_dy = s.mouse_dy;
    o.scroll_dx = s.scroll_dx;
    o.scroll_dy = s.scroll_dy;
    o.mouse_buttons_down = s.mouse_buttons_down;
    o.mouse_buttons_pressed = s.mouse_buttons_pressed;
    o.mouse_buttons_released = s.mouse_buttons_released;
}

fn inputDestroy(self: ?*c.ke_input) callconv(.c) void {
    const api = self orelse return;
    gpa.destroy(stateOf(api));
    gpa.destroy(api);
}

export fn ke_input_create(log: ?*c.ke_logger, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_input_handle {
    _ = log; // reserved; the default input system does not log
    const empty = c.ke_input_handle{ .ref = null, .destroy = null };

    const api = gpa.create(c.ke_input) catch {
        E.fail(out_error, .out_of_memory, "api allocation failed", @src());
        return empty;
    };
    const state = gpa.create(State) catch {
        gpa.destroy(api);
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return empty;
    };
    state.* = std.mem.zeroes(State);

    api.handle = state;
    api.update = &inputUpdate;
    api.is_key_pressed = &inputIsKeyPressed;
    api.is_key_down = &inputIsKeyDown;
    api.is_key_released = &inputIsKeyReleased;
    api.get_snapshot = &inputGetSnapshot;
    api.drain_events = &inputDrainEvents;
    api.on_key = &inputOnKey;
    api.on_mouse_move = &inputOnMouseMove;
    api.on_mouse_button = &inputOnMouseButton;
    api.on_mouse_scroll = &inputOnMouseScroll;

    return .{ .ref = api, .destroy = &inputDestroy };
}
