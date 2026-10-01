const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

const heap = @import("heap");
const gpa = heap.gpa;

const c = @cImport({
    @cInclude("kernel_engine/input/input.h");
    @cInclude("kernel_engine/input/default/input_default_create.h");
});

const E = @import("kerror").Errors(c);

const MAX_KEYS = c.KE_INPUT_MAX_KEYS;
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

    events: [EVENT_CAPACITY]c.ke_input_event,
    event_count: u32,
    event_overflow: bool,
    move_event: u32,
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

    s.event_count = 0;
    s.event_overflow = false;
    s.move_event = 0;
    return true;
}

fn inputOnKey(self: ?*c.ke_input, key: i32, action: i32) callconv(.c) void {
    const api = self orelse return;
    if (key < 0 or key >= MAX_KEYS) return;
    const s = stateOf(api);
    const k: usize = @intCast(key);
    if (action == c.KE_INPUT_ACTION_PRESS) {
        if (!s.keys_down[k]) s.keys_pressed[k] = true;
        s.keys_down[k] = true;
        pushEvent(s, c.KE_INPUT_EVENT_KEY_DOWN, key, 0, 0);
    } else if (action == c.KE_INPUT_ACTION_RELEASE) {
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
    if (s.move_event != 0) {
        const e = &s.events[s.move_event - 1];
        e.x = x;
        e.y = y;
        return;
    }
    pushEvent(s, c.KE_INPUT_EVENT_MOUSE_MOVE, 0, x, y);
    if (!s.event_overflow) s.move_event = s.event_count;
}

fn inputOnMouseButton(self: ?*c.ke_input, button: i32, action: i32) callconv(.c) void {
    const api = self orelse return;
    if (button < 0 or button >= c.KE_INPUT_MAX_MOUSE_BUTTONS) return;
    const s = stateOf(api);
    const mask = @as(u32, 1) << @intCast(button);
    if (action == c.KE_INPUT_ACTION_PRESS) {
        if ((s.mouse_buttons_down & mask) == 0) s.mouse_buttons_pressed |= mask;
        s.mouse_buttons_down |= mask;
        pushEvent(s, c.KE_INPUT_EVENT_MOUSE_BUTTON_DOWN, button, 0, 0);
    } else if (action == c.KE_INPUT_ACTION_RELEASE) {
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
    s.move_event = 0;
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

fn keyBit(snapshot: [*c]const c.ke_input_snapshot, words: *const [c.KE_INPUT_KEY_WORDS]u64, key: i32) c.ke_bool {
    if (snapshot == null) return 0;
    if (key < 0 or key >= MAX_KEYS) return 0;
    const idx: usize = @intCast(key);
    const bit = @as(u64, 1) << @intCast(idx % 64);
    return @intFromBool((words[idx / 64] & bit) != 0);
}

fn buttonBit(snapshot: [*c]const c.ke_input_snapshot, mask: u32, button: i32) c.ke_bool {
    if (snapshot == null) return 0;
    if (button < 0 or button >= c.KE_INPUT_MAX_MOUSE_BUTTONS) return 0;
    return @intFromBool((mask & (@as(u32, 1) << @intCast(button))) != 0);
}

fn snapshotIsKeyDown(self: ?*c.ke_input, snapshot: [*c]const c.ke_input_snapshot, key: i32) callconv(.c) c.ke_bool {
    _ = self;
    if (snapshot == null) return 0;
    return keyBit(snapshot, &snapshot.*.keys_down, key);
}

fn snapshotIsKeyPressed(self: ?*c.ke_input, snapshot: [*c]const c.ke_input_snapshot, key: i32) callconv(.c) c.ke_bool {
    _ = self;
    if (snapshot == null) return 0;
    return keyBit(snapshot, &snapshot.*.keys_pressed, key);
}

fn snapshotIsKeyReleased(self: ?*c.ke_input, snapshot: [*c]const c.ke_input_snapshot, key: i32) callconv(.c) c.ke_bool {
    _ = self;
    if (snapshot == null) return 0;
    return keyBit(snapshot, &snapshot.*.keys_released, key);
}

fn snapshotIsMouseButtonDown(self: ?*c.ke_input, snapshot: [*c]const c.ke_input_snapshot, button: i32) callconv(.c) c.ke_bool {
    _ = self;
    if (snapshot == null) return 0;
    return buttonBit(snapshot, snapshot.*.mouse_buttons_down, button);
}

fn snapshotIsMouseButtonPressed(self: ?*c.ke_input, snapshot: [*c]const c.ke_input_snapshot, button: i32) callconv(.c) c.ke_bool {
    _ = self;
    if (snapshot == null) return 0;
    return buttonBit(snapshot, snapshot.*.mouse_buttons_pressed, button);
}

fn snapshotIsMouseButtonReleased(self: ?*c.ke_input, snapshot: [*c]const c.ke_input_snapshot, button: i32) callconv(.c) c.ke_bool {
    _ = self;
    if (snapshot == null) return 0;
    return buttonBit(snapshot, snapshot.*.mouse_buttons_released, button);
}

fn inputDestroy(self: ?*c.ke_input) callconv(.c) void {
    const api = self orelse return;
    gpa.destroy(stateOf(api));
    gpa.destroy(api);
}

export fn ke_input_create(log: ?*c.ke_logger, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_input_handle {
    _ = log;
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
    api.snapshot_is_key_down = &snapshotIsKeyDown;
    api.snapshot_is_key_pressed = &snapshotIsKeyPressed;
    api.snapshot_is_key_released = &snapshotIsKeyReleased;
    api.snapshot_is_mouse_button_down = &snapshotIsMouseButtonDown;
    api.snapshot_is_mouse_button_pressed = &snapshotIsMouseButtonPressed;
    api.snapshot_is_mouse_button_released = &snapshotIsMouseButtonReleased;
    api.drain_events = &inputDrainEvents;
    api.on_key = &inputOnKey;
    api.on_mouse_move = &inputOnMouseMove;
    api.on_mouse_button = &inputOnMouseButton;
    api.on_mouse_scroll = &inputOnMouseScroll;

    return .{ .ref = api, .destroy = &inputDestroy };
}

const testing = std.testing;

test "create returns a usable handle" {
    const h = ke_input_create(null, null);
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
}

test "destroy tolerates a null input" {
    const h = ke_input_create(null, null);
    const destroy_fn = h.destroy.?;
    destroy_fn(h.ref);
    destroy_fn(null);
}

test "destroy releases a live input" {
    const h = ke_input_create(null, null);
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
}

test "update on a null self returns false" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    try testing.expect(!h.ref.*.update.?(null, null));
}

test "a key press is visible until the next update" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    _ = h.ref.*.update.?(h.ref, null);
    h.ref.*.on_key.?(h.ref, 65, c.KE_INPUT_ACTION_PRESS);
    try testing.expect(h.ref.*.is_key_pressed.?(h.ref, 65) != 0);
}

test "a pressed key appears in the snapshot bitset" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    h.ref.*.on_key.?(h.ref, 65, c.KE_INPUT_ACTION_PRESS);

    var snapshot = std.mem.zeroes(c.ke_input_snapshot);
    h.ref.*.get_snapshot.?(h.ref, &snapshot);

    const word: usize = 65 / 64;
    const bit = @as(u64, 1) << (65 % 64);
    try testing.expect((snapshot.keys_pressed[word] & bit) != 0);
}

test "mouse motion accumulates a delta within the frame" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    h.ref.*.on_mouse_move.?(h.ref, 100.0, 200.0);
    _ = h.ref.*.update.?(h.ref, null);
    h.ref.*.on_mouse_move.?(h.ref, 150.0, 180.0);

    var snapshot = std.mem.zeroes(c.ke_input_snapshot);
    h.ref.*.get_snapshot.?(h.ref, &snapshot);
    try testing.expectEqual(@as(f32, 50.0), snapshot.mouse_dx);
    try testing.expectEqual(@as(f32, -20.0), snapshot.mouse_dy);
    try testing.expectEqual(@as(f32, 150.0), snapshot.mouse_x);
    try testing.expectEqual(@as(f32, 180.0), snapshot.mouse_y);
}

test "a mouse button press shows up as both pressed and down" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    _ = h.ref.*.update.?(h.ref, null);
    h.ref.*.on_mouse_button.?(h.ref, 0, c.KE_INPUT_ACTION_PRESS);

    var snapshot = std.mem.zeroes(c.ke_input_snapshot);
    h.ref.*.get_snapshot.?(h.ref, &snapshot);
    try testing.expect((snapshot.mouse_buttons_pressed & 1) != 0);
    try testing.expect((snapshot.mouse_buttons_down & 1) != 0);
}

test "scroll deltas reach the snapshot" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    h.ref.*.on_mouse_scroll.?(h.ref, 1.5, -2.5);

    var snapshot = std.mem.zeroes(c.ke_input_snapshot);
    h.ref.*.get_snapshot.?(h.ref, &snapshot);
    try testing.expectEqual(@as(f32, 1.5), snapshot.scroll_dx);
    try testing.expectEqual(@as(f32, -2.5), snapshot.scroll_dy);
}

test "draining yields the key events in the order they arrived" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    h.ref.*.on_key.?(h.ref, 65, c.KE_INPUT_ACTION_PRESS);
    h.ref.*.on_key.?(h.ref, 65, c.KE_INPUT_ACTION_RELEASE);

    var events = std.mem.zeroes([10]c.ke_input_event);
    const count = h.ref.*.drain_events.?(h.ref, &events, 10);

    try testing.expectEqual(@as(u32, 2), count);
    try testing.expectEqual(@as(c.ke_input_event_kind, c.KE_INPUT_EVENT_KEY_DOWN), events[0].kind);
    try testing.expectEqual(@as(c.ke_input_event_kind, c.KE_INPUT_EVENT_KEY_UP), events[1].kind);
}

test "moving the cursor emits one move event carrying the latest position" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    h.ref.*.on_mouse_move.?(h.ref, 10, 20);
    h.ref.*.on_mouse_move.?(h.ref, 30, 40);
    h.ref.*.on_mouse_move.?(h.ref, 50, 60);

    var events = std.mem.zeroes([10]c.ke_input_event);
    try testing.expectEqual(@as(u32, 1), h.ref.*.drain_events.?(h.ref, &events, 10));
    try testing.expectEqual(@as(c.ke_input_event_kind, c.KE_INPUT_EVENT_MOUSE_MOVE), events[0].kind);
    try testing.expectEqual(@as(f32, 50), events[0].x);
    try testing.expectEqual(@as(f32, 60), events[0].y);
}

test "a move event keeps its place among the events that arrived around it" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    h.ref.*.on_key.?(h.ref, 65, c.KE_INPUT_ACTION_PRESS);
    h.ref.*.on_mouse_move.?(h.ref, 1, 2);
    h.ref.*.on_key.?(h.ref, 65, c.KE_INPUT_ACTION_RELEASE);
    h.ref.*.on_mouse_move.?(h.ref, 3, 4);

    var events = std.mem.zeroes([10]c.ke_input_event);
    try testing.expectEqual(@as(u32, 3), h.ref.*.drain_events.?(h.ref, &events, 10));
    try testing.expectEqual(@as(c.ke_input_event_kind, c.KE_INPUT_EVENT_KEY_DOWN), events[0].kind);
    try testing.expectEqual(@as(c.ke_input_event_kind, c.KE_INPUT_EVENT_MOUSE_MOVE), events[1].kind);
    try testing.expectEqual(@as(f32, 3), events[1].x);
    try testing.expectEqual(@as(c.ke_input_event_kind, c.KE_INPUT_EVENT_KEY_UP), events[2].kind);
}

test "a move after a drain starts a new move event" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    h.ref.*.on_mouse_move.?(h.ref, 1, 2);
    var events = std.mem.zeroes([10]c.ke_input_event);
    try testing.expectEqual(@as(u32, 1), h.ref.*.drain_events.?(h.ref, &events, 10));

    h.ref.*.on_mouse_move.?(h.ref, 7, 8);
    try testing.expectEqual(@as(u32, 1), h.ref.*.drain_events.?(h.ref, &events, 10));
    try testing.expectEqual(@as(f32, 7), events[0].x);
}

test "draining never writes past the caller capacity" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    h.ref.*.on_key.?(h.ref, 65, c.KE_INPUT_ACTION_PRESS);
    h.ref.*.on_key.?(h.ref, 66, c.KE_INPUT_ACTION_PRESS);

    var events = std.mem.zeroes([1]c.ke_input_event);
    try testing.expectEqual(@as(u32, 1), h.ref.*.drain_events.?(h.ref, &events, 1));
}

test "an overflowing event queue still drains what it kept" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    for (0..600) |_| {
        h.ref.*.on_mouse_scroll.?(h.ref, 1, 1);
    }

    var events = std.mem.zeroes([10]c.ke_input_event);
    try testing.expectEqual(@as(u32, 10), h.ref.*.drain_events.?(h.ref, &events, 10));
}

test "a held key stays down across an update while pressed clears" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    h.ref.*.on_key.?(h.ref, 10, c.KE_INPUT_ACTION_PRESS);
    try testing.expect(h.ref.*.is_key_down.?(h.ref, 10) != 0);

    _ = h.ref.*.update.?(h.ref, null);
    try testing.expect(h.ref.*.is_key_down.?(h.ref, 10) != 0);
    try testing.expect(h.ref.*.is_key_pressed.?(h.ref, 10) == 0);

    h.ref.*.on_key.?(h.ref, 10, c.KE_INPUT_ACTION_RELEASE);
    try testing.expect(h.ref.*.is_key_down.?(h.ref, 10) == 0);
    try testing.expect(h.ref.*.is_key_released.?(h.ref, 10) != 0);
}

test "an out of range key code is ignored" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    h.ref.*.on_key.?(h.ref, -1, c.KE_INPUT_ACTION_PRESS);
    h.ref.*.on_key.?(h.ref, 999, c.KE_INPUT_ACTION_PRESS);

    var events = std.mem.zeroes([4]c.ke_input_event);
    try testing.expectEqual(@as(u32, 0), h.ref.*.drain_events.?(h.ref, &events, 4));
}

test "is key down on a null self returns false" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    try testing.expectEqual(@as(c.ke_bool, 0), h.ref.*.is_key_down.?(null, 65));
}

test "is key pressed on a null self returns false" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    try testing.expectEqual(@as(c.ke_bool, 0), h.ref.*.is_key_pressed.?(null, 65));
}

test "is key released on a null self returns false" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    try testing.expectEqual(@as(c.ke_bool, 0), h.ref.*.is_key_released.?(null, 65));
}

test "get snapshot tolerates a null self or a null destination" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    h.ref.*.get_snapshot.?(null, null);

    var snapshot = std.mem.zeroes(c.ke_input_snapshot);
    h.ref.*.get_snapshot.?(null, &snapshot);
    h.ref.*.get_snapshot.?(h.ref, null);
}

test "draining with a null self or a null buffer returns zero" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    var events = std.mem.zeroes([1]c.ke_input_event);
    try testing.expectEqual(@as(u32, 0), h.ref.*.drain_events.?(null, &events, 1));
    try testing.expectEqual(@as(u32, 0), h.ref.*.drain_events.?(h.ref, null, 1));
}

test "mouse motion on a null self is ignored" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    h.ref.*.on_mouse_move.?(null, 1, 1);
}

test "snapshot accessors read the key and button bitsets" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    const api = h.ref.*;
    _ = api.update.?(h.ref, null);
    api.on_key.?(h.ref, 65, c.KE_INPUT_ACTION_PRESS);
    api.on_mouse_button.?(h.ref, 2, c.KE_INPUT_ACTION_PRESS);

    var snapshot = std.mem.zeroes(c.ke_input_snapshot);
    api.get_snapshot.?(h.ref, &snapshot);

    try testing.expectEqual(@as(c.ke_bool, 1), api.snapshot_is_key_down.?(h.ref, &snapshot, 65));
    try testing.expectEqual(@as(c.ke_bool, 1), api.snapshot_is_key_pressed.?(h.ref, &snapshot, 65));
    try testing.expectEqual(@as(c.ke_bool, 0), api.snapshot_is_key_released.?(h.ref, &snapshot, 65));
    try testing.expectEqual(@as(c.ke_bool, 0), api.snapshot_is_key_down.?(h.ref, &snapshot, 66));
    try testing.expectEqual(@as(c.ke_bool, 1), api.snapshot_is_mouse_button_down.?(h.ref, &snapshot, 2));
    try testing.expectEqual(@as(c.ke_bool, 1), api.snapshot_is_mouse_button_pressed.?(h.ref, &snapshot, 2));
    try testing.expectEqual(@as(c.ke_bool, 0), api.snapshot_is_mouse_button_released.?(h.ref, &snapshot, 2));
}

test "snapshot accessors read out-of-range codes and a null snapshot as false" {
    const h = ke_input_create(null, null);
    defer h.destroy.?(h.ref);
    const api = h.ref.*;
    var snapshot = std.mem.zeroes(c.ke_input_snapshot);

    try testing.expectEqual(@as(c.ke_bool, 0), api.snapshot_is_key_down.?(h.ref, &snapshot, -1));
    try testing.expectEqual(@as(c.ke_bool, 0), api.snapshot_is_key_down.?(h.ref, &snapshot, c.KE_INPUT_MAX_KEYS));
    try testing.expectEqual(@as(c.ke_bool, 0), api.snapshot_is_mouse_button_down.?(h.ref, &snapshot, c.KE_INPUT_MAX_MOUSE_BUTTONS));
    try testing.expectEqual(@as(c.ke_bool, 0), api.snapshot_is_key_down.?(h.ref, null, 65));
    try testing.expectEqual(@as(c.ke_bool, 0), api.snapshot_is_mouse_button_down.?(h.ref, null, 0));
}
