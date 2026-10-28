//! The keyboard and mouse state of one window, behind `ke_input`. It folds the window backend's
//! raw notifications into held state, per-frame edges and deltas, an event queue and snapshots.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_input_default").logFn };

const heap = @import("heap");
const gpa = heap.gpa;

const abi_input = @import("abi_input");
const abi_result = @import("abi_result");

const R = @import("result").Result(abi_result, .{});
const log = std.log.scoped(.input_default);

const MAX_KEYS = abi_input.KE_INPUT_MAX_KEYS;

/// Allocated by `ke_input_create` and freed by `inputDestroy`. The initial state holds no key or
/// button and an empty queue, and `move_event` zero, which means no move event is open.
/// `move_event` is the position in `events` plus one, so zero can stand for none. The queue grows
/// as events arrive; `events_dropped` counts the events it could not grow for since the last
/// `inputUpdate`, which are lost, with no move event recorded as open.
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

    events: std.ArrayList(abi_input.ke_input_event),
    events_dropped: u32,
    move_event: u32,
};

fn stateOf(self: *abi_input.ke_input) *State {
    return @ptrCast(@alignCast(self.handle));
}

/// Called by the four sinks that queue events. An event the queue cannot grow for is dropped and
/// counted in `events_dropped`.
fn pushEvent(s: *State, kind: abi_input.ke_input_event_kind, code: i32, x: f32, y: f32) void {
    s.events.append(heap.gpa, .{ .kind = kind, .code = code, .x = x, .y = y }) catch {
        s.events_dropped +|= 1;
    };
}

/// Closes the frame: the edges and deltas the queries read are those accumulated since the previous
/// call. The held keys and buttons and the mouse position carry over. A null input is ignored.
fn inputUpdate(self: ?*abi_input.ke_input) callconv(.c) void {
    const api = self orelse return;
    const s = stateOf(api);

    @memset(&s.keys_pressed, false);
    @memset(&s.keys_released, false);
    s.mouse_dx = 0;
    s.mouse_dy = 0;
    s.scroll_dx = 0;
    s.scroll_dy = 0;
    s.mouse_buttons_pressed = 0;
    s.mouse_buttons_released = 0;

    s.events.clearRetainingCapacity();
    s.events_dropped = 0;
    s.move_event = 0;
}

/// A press while the key is already held queues a key-down event but does not raise the pressed
/// edge again, so key repeat from the backend does not show up as a new press.
fn inputOnKey(self: ?*abi_input.ke_input, key: i32, action: i32) callconv(.c) void {
    const api = self orelse return;
    if (key < 0 or key >= MAX_KEYS) return;
    const s = stateOf(api);
    const k: usize = @intCast(key);
    if (action == abi_input.KE_INPUT_ACTION_PRESS) {
        if (!s.keys_down[k]) s.keys_pressed[k] = true;
        s.keys_down[k] = true;
        pushEvent(s, abi_input.KE_INPUT_EVENT_KEY_DOWN, key, 0, 0);
    } else if (action == abi_input.KE_INPUT_ACTION_RELEASE) {
        s.keys_released[k] = true;
        s.keys_down[k] = false;
        pushEvent(s, abi_input.KE_INPUT_EVENT_KEY_UP, key, 0, 0);
    }
}

/// The delta grows by the distance from the previous reported position, which is the only
/// position the next move is measured from. While a move event is open, the event is rewritten
/// with the new position instead of a second one being queued.
fn inputOnMouseMove(self: ?*abi_input.ke_input, x: f32, y: f32) callconv(.c) void {
    const api = self orelse return;
    const s = stateOf(api);
    s.mouse_dx += (x - s.mouse_x);
    s.mouse_dy += (y - s.mouse_y);
    s.mouse_x = x;
    s.mouse_y = y;
    if (s.move_event != 0) {
        const e = &s.events.items[s.move_event - 1];
        e.x = x;
        e.y = y;
        return;
    }
    const before = s.events.items.len;
    pushEvent(s, abi_input.KE_INPUT_EVENT_MOUSE_MOVE, 0, x, y);
    if (s.events.items.len > before) s.move_event = @intCast(s.events.items.len);
}

/// Keeps the same edge rule as `inputOnKey`, on the button masks rather than the key arrays.
fn inputOnMouseButton(self: ?*abi_input.ke_input, button: i32, action: i32) callconv(.c) void {
    const api = self orelse return;
    if (button < 0 or button >= abi_input.KE_INPUT_MAX_MOUSE_BUTTONS) return;
    const s = stateOf(api);
    const mask = @as(u32, 1) << @intCast(button);
    if (action == abi_input.KE_INPUT_ACTION_PRESS) {
        if ((s.mouse_buttons_down & mask) == 0) s.mouse_buttons_pressed |= mask;
        s.mouse_buttons_down |= mask;
        pushEvent(s, abi_input.KE_INPUT_EVENT_MOUSE_BUTTON_DOWN, button, 0, 0);
    } else if (action == abi_input.KE_INPUT_ACTION_RELEASE) {
        s.mouse_buttons_released |= mask;
        s.mouse_buttons_down &= ~mask;
        pushEvent(s, abi_input.KE_INPUT_EVENT_MOUSE_BUTTON_UP, button, 0, 0);
    }
}

/// Adds to the scroll delta and queues a scroll event carrying this notification's amounts.
fn inputOnMouseScroll(self: ?*abi_input.ke_input, dx: f32, dy: f32) callconv(.c) void {
    const api = self orelse return;
    const s = stateOf(api);
    s.scroll_dx += dx;
    s.scroll_dy += dy;
    pushEvent(s, abi_input.KE_INPUT_EVENT_MOUSE_SCROLL, 0, dx, dy);
}

/// Moves the oldest events, as many as the buffer holds, out of the queue; the rest stay queued
/// for the next call. A null buffer or a zero capacity returns zero and leaves the queue as it is.
fn inputDrainEvents(self: ?*abi_input.ke_input, out_buf: [*c]abi_input.ke_input_event, capacity: u32) callconv(.c) u32 {
    const api = self orelse return 0;
    if (out_buf == null or capacity == 0) return 0;
    const s = stateOf(api);
    const n: u32 = @intCast(@min(s.events.items.len, capacity));
    if (n > 0) @memcpy(out_buf[0..n], s.events.items[0..n]);
    s.events.replaceRangeAssumeCapacity(0, n, &.{});
    s.move_event = if (s.move_event > n) s.move_event - n else 0;
    return n;
}

/// True from the notification that raised the edge until the next `inputUpdate`. Out-of-range
/// codes and a null input answer false.
fn inputIsKeyPressed(self: ?*abi_input.ke_input, key: i32) callconv(.c) bool {
    const api = self orelse return false;
    if (key < 0 or key >= MAX_KEYS) return false;
    return stateOf(api).keys_pressed[@intCast(key)];
}

/// True from the notification that released the key until the next `inputUpdate`. Out-of-range
/// codes and a null input answer false.
fn inputIsKeyReleased(self: ?*abi_input.ke_input, key: i32) callconv(.c) bool {
    const api = self orelse return false;
    if (key < 0 or key >= MAX_KEYS) return false;
    return stateOf(api).keys_released[@intCast(key)];
}

/// True while the key is held, across updates. Out-of-range codes and a null input answer false.
fn inputIsKeyDown(self: ?*abi_input.ke_input, key: i32) callconv(.c) bool {
    const api = self orelse return false;
    if (key < 0 or key >= MAX_KEYS) return false;
    return stateOf(api).keys_down[@intCast(key)];
}

/// Writes the whole state into the caller's struct, which is zeroed first. The snapshot queries
/// read only this copy, so a snapshot taken before a later tick does not change with it.
fn inputGetSnapshot(self: ?*abi_input.ke_input, out: [*c]abi_input.ke_input_snapshot) callconv(.c) void {
    const api = self orelse return;
    if (out == null) return;
    const s = stateOf(api);
    const o: *abi_input.ke_input_snapshot = @ptrCast(out);
    o.* = std.mem.zeroes(abi_input.ke_input_snapshot);

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
    o.events_dropped = s.events_dropped;
}

/// Reads one key from a snapshot's packed words; a null snapshot or out-of-range key is false.
fn keyBit(snapshot: [*c]const abi_input.ke_input_snapshot, words: *const [abi_input.KE_INPUT_KEY_WORDS]u64, key: i32) bool {
    if (snapshot == null) return false;
    if (key < 0 or key >= MAX_KEYS) return false;
    const idx: usize = @intCast(key);
    const bit = @as(u64, 1) << @intCast(idx % 64);
    return (words[idx / 64] & bit) != 0;
}

/// Reads one button from a snapshot's mask; a null snapshot or out-of-range button is false.
fn buttonBit(snapshot: [*c]const abi_input.ke_input_snapshot, mask: u32, button: i32) bool {
    if (snapshot == null) return false;
    if (button < 0 or button >= abi_input.KE_INPUT_MAX_MOUSE_BUTTONS) return false;
    return (mask & (@as(u32, 1) << @intCast(button))) != 0;
}

fn snapshotIsKeyDown(self: ?*abi_input.ke_input, snapshot: [*c]const abi_input.ke_input_snapshot, key: i32) callconv(.c) bool {
    _ = self;
    if (snapshot == null) return false;
    return keyBit(snapshot, &snapshot.*.keys_down, key);
}

fn snapshotIsKeyPressed(self: ?*abi_input.ke_input, snapshot: [*c]const abi_input.ke_input_snapshot, key: i32) callconv(.c) bool {
    _ = self;
    if (snapshot == null) return false;
    return keyBit(snapshot, &snapshot.*.keys_pressed, key);
}

fn snapshotIsKeyReleased(self: ?*abi_input.ke_input, snapshot: [*c]const abi_input.ke_input_snapshot, key: i32) callconv(.c) bool {
    _ = self;
    if (snapshot == null) return false;
    return keyBit(snapshot, &snapshot.*.keys_released, key);
}

fn snapshotIsMouseButtonDown(self: ?*abi_input.ke_input, snapshot: [*c]const abi_input.ke_input_snapshot, button: i32) callconv(.c) bool {
    _ = self;
    if (snapshot == null) return false;
    return buttonBit(snapshot, snapshot.*.mouse_buttons_down, button);
}

fn snapshotIsMouseButtonPressed(self: ?*abi_input.ke_input, snapshot: [*c]const abi_input.ke_input_snapshot, button: i32) callconv(.c) bool {
    _ = self;
    if (snapshot == null) return false;
    return buttonBit(snapshot, snapshot.*.mouse_buttons_pressed, button);
}

fn snapshotIsMouseButtonReleased(self: ?*abi_input.ke_input, snapshot: [*c]const abi_input.ke_input_snapshot, button: i32) callconv(.c) bool {
    _ = self;
    if (snapshot == null) return false;
    return buttonBit(snapshot, snapshot.*.mouse_buttons_released, button);
}

/// Frees the `State` and the vtable block that `ke_input_create` allocated; a null input is
/// ignored.
fn inputDestroy(self: ?*abi_input.ke_input) callconv(.c) void {
    const api = self orelse return;
    stateOf(api).events.deinit(gpa);
    gpa.destroy(stateOf(api));
    gpa.destroy(api);
}

/// Builds the vtable and its `State`, starting with the zeroed state, into a handle whose
/// `destroy` is `inputDestroy`. Fails with out of memory, leaving nothing allocated.
export fn ke_input_create(out_input: ?*abi_input.ke_input_handle) callconv(.c) abi_result.ke_result {
    const out = out_input orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    out.* = create() catch |err| {
        log.warn("creating the input system failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn create() R.Error!abi_input.ke_input_handle {
    const api = gpa.create(abi_input.ke_input) catch return error.OutOfMemory;
    errdefer gpa.destroy(api);
    const state = gpa.create(State) catch return error.OutOfMemory;
    state.* = std.mem.zeroes(State);
    state.events = .empty;

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

fn created() !abi_input.ke_input_handle {
    var h: abi_input.ke_input_handle = undefined;
    try R.check(ke_input_create(&h));
    return h;
}

test "create returns a usable handle" {
    const h = try created();
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
}

test "destroy tolerates a null input" {
    const h = try created();
    const destroy_fn = h.destroy.?;
    destroy_fn(h.ref);
    destroy_fn(null);
}

test "destroy releases a live input" {
    const h = try created();
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
}

test "update on a null self is ignored" {
    const h = try created();
    defer h.destroy.?(h.ref);
    h.ref.?.update.?(null);
}

test "a null handle to fill is refused as an invalid argument" {
    try testing.expectError(error.InvalidArgument, R.check(ke_input_create(null)));
}

test "a key press is visible until the next update" {
    const h = try created();
    defer h.destroy.?(h.ref);
    h.ref.?.update.?(h.ref);
    h.ref.?.on_key.?(h.ref, 65, abi_input.KE_INPUT_ACTION_PRESS);
    try testing.expect(h.ref.?.is_key_pressed.?(h.ref, 65));
}

test "a pressed key appears in the snapshot bitset" {
    const h = try created();
    defer h.destroy.?(h.ref);
    h.ref.?.on_key.?(h.ref, 65, abi_input.KE_INPUT_ACTION_PRESS);

    var snapshot = std.mem.zeroes(abi_input.ke_input_snapshot);
    h.ref.?.get_snapshot.?(h.ref, &snapshot);

    const word: usize = 65 / 64;
    const bit = @as(u64, 1) << (65 % 64);
    try testing.expect((snapshot.keys_pressed[word] & bit) != 0);
}

test "mouse motion accumulates a delta within the frame" {
    const h = try created();
    defer h.destroy.?(h.ref);
    h.ref.?.on_mouse_move.?(h.ref, 100.0, 200.0);
    h.ref.?.update.?(h.ref);
    h.ref.?.on_mouse_move.?(h.ref, 150.0, 180.0);

    var snapshot = std.mem.zeroes(abi_input.ke_input_snapshot);
    h.ref.?.get_snapshot.?(h.ref, &snapshot);
    try testing.expectEqual(@as(f32, 50.0), snapshot.mouse_dx);
    try testing.expectEqual(@as(f32, -20.0), snapshot.mouse_dy);
    try testing.expectEqual(@as(f32, 150.0), snapshot.mouse_x);
    try testing.expectEqual(@as(f32, 180.0), snapshot.mouse_y);
}

test "a mouse button press shows up as both pressed and down" {
    const h = try created();
    defer h.destroy.?(h.ref);
    h.ref.?.update.?(h.ref);
    h.ref.?.on_mouse_button.?(h.ref, 0, abi_input.KE_INPUT_ACTION_PRESS);

    var snapshot = std.mem.zeroes(abi_input.ke_input_snapshot);
    h.ref.?.get_snapshot.?(h.ref, &snapshot);
    try testing.expect((snapshot.mouse_buttons_pressed & 1) != 0);
    try testing.expect((snapshot.mouse_buttons_down & 1) != 0);
}

test "scroll deltas reach the snapshot" {
    const h = try created();
    defer h.destroy.?(h.ref);
    h.ref.?.on_mouse_scroll.?(h.ref, 1.5, -2.5);

    var snapshot = std.mem.zeroes(abi_input.ke_input_snapshot);
    h.ref.?.get_snapshot.?(h.ref, &snapshot);
    try testing.expectEqual(@as(f32, 1.5), snapshot.scroll_dx);
    try testing.expectEqual(@as(f32, -2.5), snapshot.scroll_dy);
}

test "the snapshot reports the events dropped this frame and an update clears the count" {
    const h = try created();
    defer h.destroy.?(h.ref);
    stateOf(h.ref.?).events_dropped = 3;

    var snapshot = std.mem.zeroes(abi_input.ke_input_snapshot);
    h.ref.?.get_snapshot.?(h.ref, &snapshot);
    try testing.expectEqual(@as(u32, 3), snapshot.events_dropped);

    h.ref.?.update.?(h.ref);
    h.ref.?.get_snapshot.?(h.ref, &snapshot);
    try testing.expectEqual(@as(u32, 0), snapshot.events_dropped);
}

test "draining yields the key events in the order they arrived" {
    const h = try created();
    defer h.destroy.?(h.ref);
    h.ref.?.on_key.?(h.ref, 65, abi_input.KE_INPUT_ACTION_PRESS);
    h.ref.?.on_key.?(h.ref, 65, abi_input.KE_INPUT_ACTION_RELEASE);

    var events = std.mem.zeroes([10]abi_input.ke_input_event);
    const count = h.ref.?.drain_events.?(h.ref, &events, 10);

    try testing.expectEqual(@as(u32, 2), count);
    try testing.expectEqual(@as(abi_input.ke_input_event_kind, abi_input.KE_INPUT_EVENT_KEY_DOWN), events[0].kind);
    try testing.expectEqual(@as(abi_input.ke_input_event_kind, abi_input.KE_INPUT_EVENT_KEY_UP), events[1].kind);
}

test "moving the cursor emits one move event carrying the latest position" {
    const h = try created();
    defer h.destroy.?(h.ref);
    h.ref.?.on_mouse_move.?(h.ref, 10, 20);
    h.ref.?.on_mouse_move.?(h.ref, 30, 40);
    h.ref.?.on_mouse_move.?(h.ref, 50, 60);

    var events = std.mem.zeroes([10]abi_input.ke_input_event);
    try testing.expectEqual(@as(u32, 1), h.ref.?.drain_events.?(h.ref, &events, 10));
    try testing.expectEqual(@as(abi_input.ke_input_event_kind, abi_input.KE_INPUT_EVENT_MOUSE_MOVE), events[0].kind);
    try testing.expectEqual(@as(f32, 50), events[0].x);
    try testing.expectEqual(@as(f32, 60), events[0].y);
}

test "a move event keeps its place among the events that arrived around it" {
    const h = try created();
    defer h.destroy.?(h.ref);
    h.ref.?.on_key.?(h.ref, 65, abi_input.KE_INPUT_ACTION_PRESS);
    h.ref.?.on_mouse_move.?(h.ref, 1, 2);
    h.ref.?.on_key.?(h.ref, 65, abi_input.KE_INPUT_ACTION_RELEASE);
    h.ref.?.on_mouse_move.?(h.ref, 3, 4);

    var events = std.mem.zeroes([10]abi_input.ke_input_event);
    try testing.expectEqual(@as(u32, 3), h.ref.?.drain_events.?(h.ref, &events, 10));
    try testing.expectEqual(@as(abi_input.ke_input_event_kind, abi_input.KE_INPUT_EVENT_KEY_DOWN), events[0].kind);
    try testing.expectEqual(@as(abi_input.ke_input_event_kind, abi_input.KE_INPUT_EVENT_MOUSE_MOVE), events[1].kind);
    try testing.expectEqual(@as(f32, 3), events[1].x);
    try testing.expectEqual(@as(abi_input.ke_input_event_kind, abi_input.KE_INPUT_EVENT_KEY_UP), events[2].kind);
}

test "a move after a drain starts a new move event" {
    const h = try created();
    defer h.destroy.?(h.ref);
    h.ref.?.on_mouse_move.?(h.ref, 1, 2);
    var events = std.mem.zeroes([10]abi_input.ke_input_event);
    try testing.expectEqual(@as(u32, 1), h.ref.?.drain_events.?(h.ref, &events, 10));

    h.ref.?.on_mouse_move.?(h.ref, 7, 8);
    try testing.expectEqual(@as(u32, 1), h.ref.?.drain_events.?(h.ref, &events, 10));
    try testing.expectEqual(@as(f32, 7), events[0].x);
}

test "draining never writes past the caller capacity and keeps the rest for the next drain" {
    const h = try created();
    defer h.destroy.?(h.ref);
    h.ref.?.on_key.?(h.ref, 65, abi_input.KE_INPUT_ACTION_PRESS);
    h.ref.?.on_key.?(h.ref, 66, abi_input.KE_INPUT_ACTION_PRESS);

    var events = std.mem.zeroes([1]abi_input.ke_input_event);
    try testing.expectEqual(@as(u32, 1), h.ref.?.drain_events.?(h.ref, &events, 1));
    try testing.expectEqual(@as(i32, 65), events[0].code);
    try testing.expectEqual(@as(u32, 1), h.ref.?.drain_events.?(h.ref, &events, 1));
    try testing.expectEqual(@as(i32, 66), events[0].code);
    try testing.expectEqual(@as(u32, 0), h.ref.?.drain_events.?(h.ref, &events, 1));
}

test "the event queue keeps every event of a busy frame" {
    const h = try created();
    defer h.destroy.?(h.ref);
    for (0..2000) |_| {
        h.ref.?.on_mouse_scroll.?(h.ref, 1, 1);
    }

    var events = std.mem.zeroes([4096]abi_input.ke_input_event);
    try testing.expectEqual(@as(u32, 2000), h.ref.?.drain_events.?(h.ref, &events, events.len));
}

test "a held key stays down across an update while pressed clears" {
    const h = try created();
    defer h.destroy.?(h.ref);
    h.ref.?.on_key.?(h.ref, 10, abi_input.KE_INPUT_ACTION_PRESS);
    try testing.expect(h.ref.?.is_key_down.?(h.ref, 10));

    h.ref.?.update.?(h.ref);
    try testing.expect(h.ref.?.is_key_down.?(h.ref, 10));
    try testing.expect(!h.ref.?.is_key_pressed.?(h.ref, 10));

    h.ref.?.on_key.?(h.ref, 10, abi_input.KE_INPUT_ACTION_RELEASE);
    try testing.expect(!h.ref.?.is_key_down.?(h.ref, 10));
    try testing.expect(h.ref.?.is_key_released.?(h.ref, 10));
}

test "an out of range key code is ignored" {
    const h = try created();
    defer h.destroy.?(h.ref);
    h.ref.?.on_key.?(h.ref, -1, abi_input.KE_INPUT_ACTION_PRESS);
    h.ref.?.on_key.?(h.ref, 999, abi_input.KE_INPUT_ACTION_PRESS);

    var events = std.mem.zeroes([4]abi_input.ke_input_event);
    try testing.expectEqual(@as(u32, 0), h.ref.?.drain_events.?(h.ref, &events, 4));
}

test "is key down on a null self returns false" {
    const h = try created();
    defer h.destroy.?(h.ref);
    try testing.expectEqual(false, h.ref.?.is_key_down.?(null, 65));
}

test "is key pressed on a null self returns false" {
    const h = try created();
    defer h.destroy.?(h.ref);
    try testing.expectEqual(false, h.ref.?.is_key_pressed.?(null, 65));
}

test "is key released on a null self returns false" {
    const h = try created();
    defer h.destroy.?(h.ref);
    try testing.expectEqual(false, h.ref.?.is_key_released.?(null, 65));
}

test "get snapshot tolerates a null self or a null destination" {
    const h = try created();
    defer h.destroy.?(h.ref);
    h.ref.?.get_snapshot.?(null, null);

    var snapshot = std.mem.zeroes(abi_input.ke_input_snapshot);
    h.ref.?.get_snapshot.?(null, &snapshot);
    h.ref.?.get_snapshot.?(h.ref, null);
}

test "draining with a null self or a null buffer returns zero" {
    const h = try created();
    defer h.destroy.?(h.ref);
    var events = std.mem.zeroes([1]abi_input.ke_input_event);
    try testing.expectEqual(@as(u32, 0), h.ref.?.drain_events.?(null, &events, 1));
    try testing.expectEqual(@as(u32, 0), h.ref.?.drain_events.?(h.ref, null, 1));
}

test "mouse motion on a null self is ignored" {
    const h = try created();
    defer h.destroy.?(h.ref);
    h.ref.?.on_mouse_move.?(null, 1, 1);
}

test "snapshot accessors read the key and button bitsets" {
    const h = try created();
    defer h.destroy.?(h.ref);
    const api = h.ref.?.*;
    api.update.?(h.ref);
    api.on_key.?(h.ref, 65, abi_input.KE_INPUT_ACTION_PRESS);
    api.on_mouse_button.?(h.ref, 2, abi_input.KE_INPUT_ACTION_PRESS);

    var snapshot = std.mem.zeroes(abi_input.ke_input_snapshot);
    api.get_snapshot.?(h.ref, &snapshot);

    try testing.expectEqual(true, api.snapshot_is_key_down.?(h.ref, &snapshot, 65));
    try testing.expectEqual(true, api.snapshot_is_key_pressed.?(h.ref, &snapshot, 65));
    try testing.expectEqual(false, api.snapshot_is_key_released.?(h.ref, &snapshot, 65));
    try testing.expectEqual(false, api.snapshot_is_key_down.?(h.ref, &snapshot, 66));
    try testing.expectEqual(true, api.snapshot_is_mouse_button_down.?(h.ref, &snapshot, 2));
    try testing.expectEqual(true, api.snapshot_is_mouse_button_pressed.?(h.ref, &snapshot, 2));
    try testing.expectEqual(false, api.snapshot_is_mouse_button_released.?(h.ref, &snapshot, 2));
}

test "snapshot accessors read out-of-range codes and a null snapshot as false" {
    const h = try created();
    defer h.destroy.?(h.ref);
    const api = h.ref.?.*;
    var snapshot = std.mem.zeroes(abi_input.ke_input_snapshot);

    try testing.expectEqual(false, api.snapshot_is_key_down.?(h.ref, &snapshot, -1));
    try testing.expectEqual(false, api.snapshot_is_key_down.?(h.ref, &snapshot, abi_input.KE_INPUT_MAX_KEYS));
    try testing.expectEqual(false, api.snapshot_is_mouse_button_down.?(h.ref, &snapshot, abi_input.KE_INPUT_MAX_MOUSE_BUTTONS));
    try testing.expectEqual(false, api.snapshot_is_key_down.?(h.ref, null, 65));
    try testing.expectEqual(false, api.snapshot_is_mouse_button_down.?(h.ref, null, 0));
}

test "creating and destroying the input leaves no block allocated" {
    const h = try created();
    h.ref.?.on_key.?(h.ref, 65, abi_input.KE_INPUT_ACTION_PRESS);
    h.ref.?.on_mouse_move.?(h.ref, 1, 2);
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}
