//! The input actions map: named actions bound to keys and mouse buttons, evaluated once per frame
//! against an input snapshot and polled by a game.

const abi_input_actions = @import("abi_input_actions");
const std = @import("std");

const c = @import("c");
const abi_input = @import("abi_input");
const abi_result = @import("abi_result");
const heap = @import("heap");
const abi_io = @import("abi_io");
const file_read = @import("file_read.zig");

const R = @import("result").Result(.{});
const log = std.log.scoped(.framework);

const action_name_max = 64;

const action_initial_capacity: u32 = 8;
const binding_initial_capacity: u32 = 4;

const key_bit_count: c_int = @intCast(
    @typeInfo(@FieldType(abi_input.c.ke_input_snapshot, "keys_down")).array.len * 64,
);

const KeyNameEntry = struct { name: []const u8, code: c_int };

const key_table = [_]KeyNameEntry{
    .{ .name = "Unknown", .code = abi_input.c.KE_KEY_UNKNOWN },                .{ .name = "Space", .code = abi_input.c.KE_KEY_SPACE },
    .{ .name = "Apostrophe", .code = abi_input.c.KE_KEY_APOSTROPHE },          .{ .name = "Comma", .code = abi_input.c.KE_KEY_COMMA },
    .{ .name = "Minus", .code = abi_input.c.KE_KEY_MINUS },                    .{ .name = "Period", .code = abi_input.c.KE_KEY_PERIOD },
    .{ .name = "Slash", .code = abi_input.c.KE_KEY_SLASH },                    .{ .name = "Number0", .code = abi_input.c.KE_KEY_NUMBER_0 },
    .{ .name = "Number1", .code = abi_input.c.KE_KEY_NUMBER_1 },               .{ .name = "Number2", .code = abi_input.c.KE_KEY_NUMBER_2 },
    .{ .name = "Number3", .code = abi_input.c.KE_KEY_NUMBER_3 },               .{ .name = "Number4", .code = abi_input.c.KE_KEY_NUMBER_4 },
    .{ .name = "Number5", .code = abi_input.c.KE_KEY_NUMBER_5 },               .{ .name = "Number6", .code = abi_input.c.KE_KEY_NUMBER_6 },
    .{ .name = "Number7", .code = abi_input.c.KE_KEY_NUMBER_7 },               .{ .name = "Number8", .code = abi_input.c.KE_KEY_NUMBER_8 },
    .{ .name = "Number9", .code = abi_input.c.KE_KEY_NUMBER_9 },               .{ .name = "Semicolon", .code = abi_input.c.KE_KEY_SEMICOLON },
    .{ .name = "Equal", .code = abi_input.c.KE_KEY_EQUAL },                    .{ .name = "A", .code = abi_input.c.KE_KEY_A },
    .{ .name = "B", .code = abi_input.c.KE_KEY_B },                            .{ .name = "C", .code = abi_input.c.KE_KEY_C },
    .{ .name = "D", .code = abi_input.c.KE_KEY_D },                            .{ .name = "E", .code = abi_input.c.KE_KEY_E },
    .{ .name = "F", .code = abi_input.c.KE_KEY_F },                            .{ .name = "G", .code = abi_input.c.KE_KEY_G },
    .{ .name = "H", .code = abi_input.c.KE_KEY_H },                            .{ .name = "I", .code = abi_input.c.KE_KEY_I },
    .{ .name = "J", .code = abi_input.c.KE_KEY_J },                            .{ .name = "K", .code = abi_input.c.KE_KEY_K },
    .{ .name = "L", .code = abi_input.c.KE_KEY_L },                            .{ .name = "M", .code = abi_input.c.KE_KEY_M },
    .{ .name = "N", .code = abi_input.c.KE_KEY_N },                            .{ .name = "O", .code = abi_input.c.KE_KEY_O },
    .{ .name = "P", .code = abi_input.c.KE_KEY_P },                            .{ .name = "Q", .code = abi_input.c.KE_KEY_Q },
    .{ .name = "R", .code = abi_input.c.KE_KEY_R },                            .{ .name = "S", .code = abi_input.c.KE_KEY_S },
    .{ .name = "T", .code = abi_input.c.KE_KEY_T },                            .{ .name = "U", .code = abi_input.c.KE_KEY_U },
    .{ .name = "V", .code = abi_input.c.KE_KEY_V },                            .{ .name = "W", .code = abi_input.c.KE_KEY_W },
    .{ .name = "X", .code = abi_input.c.KE_KEY_X },                            .{ .name = "Y", .code = abi_input.c.KE_KEY_Y },
    .{ .name = "Z", .code = abi_input.c.KE_KEY_Z },                            .{ .name = "LeftBracket", .code = abi_input.c.KE_KEY_LEFT_BRACKET },
    .{ .name = "BackSlash", .code = abi_input.c.KE_KEY_BACKSLASH },            .{ .name = "RightBracket", .code = abi_input.c.KE_KEY_RIGHT_BRACKET },
    .{ .name = "GraveAccent", .code = abi_input.c.KE_KEY_GRAVE_ACCENT },       .{ .name = "World1", .code = abi_input.c.KE_KEY_WORLD_1 },
    .{ .name = "World2", .code = abi_input.c.KE_KEY_WORLD_2 },                 .{ .name = "Escape", .code = abi_input.c.KE_KEY_ESCAPE },
    .{ .name = "Enter", .code = abi_input.c.KE_KEY_ENTER },                    .{ .name = "Tab", .code = abi_input.c.KE_KEY_TAB },
    .{ .name = "Backspace", .code = abi_input.c.KE_KEY_BACKSPACE },            .{ .name = "Insert", .code = abi_input.c.KE_KEY_INSERT },
    .{ .name = "Delete", .code = abi_input.c.KE_KEY_DELETE },                  .{ .name = "Right", .code = abi_input.c.KE_KEY_RIGHT },
    .{ .name = "Left", .code = abi_input.c.KE_KEY_LEFT },                      .{ .name = "Down", .code = abi_input.c.KE_KEY_DOWN },
    .{ .name = "Up", .code = abi_input.c.KE_KEY_UP },                          .{ .name = "PageUp", .code = abi_input.c.KE_KEY_PAGE_UP },
    .{ .name = "PageDown", .code = abi_input.c.KE_KEY_PAGE_DOWN },             .{ .name = "Home", .code = abi_input.c.KE_KEY_HOME },
    .{ .name = "End", .code = abi_input.c.KE_KEY_END },                        .{ .name = "CapsLock", .code = abi_input.c.KE_KEY_CAPS_LOCK },
    .{ .name = "ScrollLock", .code = abi_input.c.KE_KEY_SCROLL_LOCK },         .{ .name = "NumLock", .code = abi_input.c.KE_KEY_NUM_LOCK },
    .{ .name = "PrintScreen", .code = abi_input.c.KE_KEY_PRINT_SCREEN },       .{ .name = "Pause", .code = abi_input.c.KE_KEY_PAUSE },
    .{ .name = "F1", .code = abi_input.c.KE_KEY_F1 },                          .{ .name = "F2", .code = abi_input.c.KE_KEY_F2 },
    .{ .name = "F3", .code = abi_input.c.KE_KEY_F3 },                          .{ .name = "F4", .code = abi_input.c.KE_KEY_F4 },
    .{ .name = "F5", .code = abi_input.c.KE_KEY_F5 },                          .{ .name = "F6", .code = abi_input.c.KE_KEY_F6 },
    .{ .name = "F7", .code = abi_input.c.KE_KEY_F7 },                          .{ .name = "F8", .code = abi_input.c.KE_KEY_F8 },
    .{ .name = "F9", .code = abi_input.c.KE_KEY_F9 },                          .{ .name = "F10", .code = abi_input.c.KE_KEY_F10 },
    .{ .name = "F11", .code = abi_input.c.KE_KEY_F11 },                        .{ .name = "F12", .code = abi_input.c.KE_KEY_F12 },
    .{ .name = "F13", .code = abi_input.c.KE_KEY_F13 },                        .{ .name = "F14", .code = abi_input.c.KE_KEY_F14 },
    .{ .name = "F15", .code = abi_input.c.KE_KEY_F15 },                        .{ .name = "F16", .code = abi_input.c.KE_KEY_F16 },
    .{ .name = "F17", .code = abi_input.c.KE_KEY_F17 },                        .{ .name = "F18", .code = abi_input.c.KE_KEY_F18 },
    .{ .name = "F19", .code = abi_input.c.KE_KEY_F19 },                        .{ .name = "F20", .code = abi_input.c.KE_KEY_F20 },
    .{ .name = "F21", .code = abi_input.c.KE_KEY_F21 },                        .{ .name = "F22", .code = abi_input.c.KE_KEY_F22 },
    .{ .name = "F23", .code = abi_input.c.KE_KEY_F23 },                        .{ .name = "F24", .code = abi_input.c.KE_KEY_F24 },
    .{ .name = "F25", .code = abi_input.c.KE_KEY_F25 },                        .{ .name = "Keypad0", .code = abi_input.c.KE_KEY_KEYPAD_0 },
    .{ .name = "Keypad1", .code = abi_input.c.KE_KEY_KEYPAD_1 },               .{ .name = "Keypad2", .code = abi_input.c.KE_KEY_KEYPAD_2 },
    .{ .name = "Keypad3", .code = abi_input.c.KE_KEY_KEYPAD_3 },               .{ .name = "Keypad4", .code = abi_input.c.KE_KEY_KEYPAD_4 },
    .{ .name = "Keypad5", .code = abi_input.c.KE_KEY_KEYPAD_5 },               .{ .name = "Keypad6", .code = abi_input.c.KE_KEY_KEYPAD_6 },
    .{ .name = "Keypad7", .code = abi_input.c.KE_KEY_KEYPAD_7 },               .{ .name = "Keypad8", .code = abi_input.c.KE_KEY_KEYPAD_8 },
    .{ .name = "Keypad9", .code = abi_input.c.KE_KEY_KEYPAD_9 },               .{ .name = "KeypadDecimal", .code = abi_input.c.KE_KEY_KEYPAD_DECIMAL },
    .{ .name = "KeypadDivide", .code = abi_input.c.KE_KEY_KEYPAD_DIVIDE },     .{ .name = "KeypadMultiply", .code = abi_input.c.KE_KEY_KEYPAD_MULTIPLY },
    .{ .name = "KeypadSubtract", .code = abi_input.c.KE_KEY_KEYPAD_SUBTRACT }, .{ .name = "KeypadAdd", .code = abi_input.c.KE_KEY_KEYPAD_ADD },
    .{ .name = "KeypadEnter", .code = abi_input.c.KE_KEY_KEYPAD_ENTER },       .{ .name = "KeypadEqual", .code = abi_input.c.KE_KEY_KEYPAD_EQUAL },
    .{ .name = "ShiftLeft", .code = abi_input.c.KE_KEY_SHIFT_LEFT },           .{ .name = "ControlLeft", .code = abi_input.c.KE_KEY_CONTROL_LEFT },
    .{ .name = "AltLeft", .code = abi_input.c.KE_KEY_ALT_LEFT },               .{ .name = "SuperLeft", .code = abi_input.c.KE_KEY_SUPER_LEFT },
    .{ .name = "ShiftRight", .code = abi_input.c.KE_KEY_SHIFT_RIGHT },         .{ .name = "ControlRight", .code = abi_input.c.KE_KEY_CONTROL_RIGHT },
    .{ .name = "AltRight", .code = abi_input.c.KE_KEY_ALT_RIGHT },             .{ .name = "SuperRight", .code = abi_input.c.KE_KEY_SUPER_RIGHT },
    .{ .name = "Menu", .code = abi_input.c.KE_KEY_MENU },
};

const mouse_table = [_]KeyNameEntry{
    .{ .name = "Left", .code = abi_input.c.KE_MOUSE_BUTTON_LEFT },
    .{ .name = "Right", .code = abi_input.c.KE_MOUSE_BUTTON_RIGHT },
    .{ .name = "Middle", .code = abi_input.c.KE_MOUSE_BUTTON_MIDDLE },
};

/// A name that matches no entry gives `KE_KEY_UNKNOWN`, which `isKeyDown` never reports as held.
fn lookupKey(name: [*c]const u8) c_int {
    if (name == null) return abi_input.c.KE_KEY_UNKNOWN;
    const n = std.mem.span(name);
    for (key_table) |entry| {
        if (std.mem.eql(u8, entry.name, n)) return entry.code;
    }
    return abi_input.c.KE_KEY_UNKNOWN;
}

/// A name that matches no entry gives a negative value, which `isMouseDown` never reports as held.
fn lookupMouseButton(name: [*c]const u8) c_int {
    if (name == null) return -1;
    const n = std.mem.span(name);
    for (mouse_table) |entry| {
        if (std.mem.eql(u8, entry.name, n)) return entry.code;
    }
    return -1;
}

fn parseActionType(s: [*c]const u8) ?abi_input_actions.c.ke_action_type {
    const t = std.mem.span(s);
    if (std.mem.eql(u8, t, "Button")) return abi_input_actions.c.KE_ACTION_TYPE_BUTTON;
    if (std.mem.eql(u8, t, "Axis1D")) return abi_input_actions.c.KE_ACTION_TYPE_AXIS1D;
    if (std.mem.eql(u8, t, "Axis2D")) return abi_input_actions.c.KE_ACTION_TYPE_AXIS2D;
    if (std.mem.eql(u8, t, "Axis3D")) return abi_input_actions.c.KE_ACTION_TYPE_AXIS3D;
    return null;
}

const BindingKind = enum(u8) { key, key_pair, key_quad, mouse_button };

/// One binding of an action. Which of `k0` through `k3` it reads depends on `kind`: a key or a
/// mouse button reads `k0` alone, a key pair reads `k0` as its negative key and `k1` as its
/// positive key, and a key quad reads `k0` up, `k1` down, `k2` left and `k3` right. The unused
/// fields stay zero.
const Binding = struct {
    kind: BindingKind,
    k0: c_int = 0,
    k1: c_int = 0,
    k2: c_int = 0,
    k3: c_int = 0,
};

/// One named action, held by value in the `actions` array of its `State`. `name` is NUL-terminated
/// within its buffer. `bindings` stays null until the first binding is appended, and its buffer is
/// freed only by `clearActions`. The current values are written by `vtEvaluate`, which copies them
/// to the previous ones before sampling. The edge queries compare `curr_active` with
/// `prev_active`.
const Action = struct {
    name: [action_name_max]u8,
    type: abi_input_actions.c.ke_action_type,
    bindings: ?[*]Binding,
    binding_count: u32,
    binding_capacity: u32,

    curr_x: f32,
    curr_y: f32,
    curr_z: f32,
    prev_x: f32,
    prev_y: f32,
    prev_z: f32,
    curr_active: bool,
    prev_active: bool,

    fn blank() Action {
        return .{
            .name = [_]u8{0} ** action_name_max,
            .type = abi_input_actions.c.KE_ACTION_TYPE_BUTTON,
            .bindings = null,
            .binding_count = 0,
            .binding_capacity = 0,
            .curr_x = 0,
            .curr_y = 0,
            .curr_z = 0,
            .prev_x = 0,
            .prev_y = 0,
            .prev_z = 0,
            .curr_active = false,
            .prev_active = false,
        };
    }
};

/// The object behind the handle that `ke_input_actions_create` returns, freed by `vtDestroy`. `api`
/// is the vtable the handle's ref points at, and its `handle` field points back at this `State`,
/// which is how each vtable function reaches it through `stateOf`. `actions` stays null until the
/// first action is added or loaded.
///
/// An action id is the index of the action in `actions`, so appending keeps ids valid and a load
/// invalidates them. A binding names no key by text: names such as "Space" or "Left" are turned
/// into codes by `lookupKey` and `lookupMouseButton` when a binding is created from a file, so
/// evaluation deals only in codes. `vtEvaluate` moves each action's current values to its
/// previous ones, samples every binding and keeps the result; the queries only read those stored
/// values, never the snapshot, which is how they report both a held state and a press or release
/// edge. Slots that take an error output report an invalid argument for a null handle or
/// pointer; those that return a sentinel set no error. Nothing here locks, so one handle is not
/// safe to use from several threads at once.
const State = struct {
    api: abi_input_actions.c.ke_input_actions,
    actions: ?[*]Action,
    action_count: u32,
    action_capacity: u32,
    io: *abi_io.c.ke_io,
};

fn stateOf(self: *abi_input_actions.c.ke_input_actions) *State {
    return @ptrCast(@alignCast(self.handle));
}

/// On allocation failure it returns null and leaves the old buffer and its capacity untouched, so
/// the caller keeps every item it had. On success the old buffer is freed, so the caller must store
/// the returned pointer.
fn growArray(
    comptime T: type,
    buf: ?[*]T,
    count: u32,
    capacity: *u32,
    needed: u32,
    initial: u32,
) ??[*]T {
    if (capacity.* >= needed) return buf;
    var cap = if (capacity.* != 0) capacity.* else initial;
    while (cap < needed) cap *= 2;
    const new_buf = heap.gpa.alloc(T, cap) catch return null;
    if (buf) |old| {
        @memcpy(new_buf[0..count], old[0..count]);
        heap.gpa.free(old[0..capacity.*]);
    }
    capacity.* = cap;
    return new_buf.ptr;
}

fn ensureActionCapacity(s: *State, needed: u32) bool {
    const grown = growArray(Action, s.actions, s.action_count, &s.action_capacity, needed, action_initial_capacity) orelse return false;
    s.actions = grown;
    return true;
}

fn ensureBindingCapacity(a: *Action, needed: u32) bool {
    const grown = growArray(Binding, a.bindings, a.binding_count, &a.binding_capacity, needed, binding_initial_capacity) orelse return false;
    a.bindings = grown;
    return true;
}

/// Frees the bindings of every action and forgets the actions, but keeps the action array allocated
/// at its capacity, so the next add or load reuses it.
fn clearActions(s: *State) void {
    if (s.actions) |actions| {
        for (actions[0..s.action_count]) |*a| {
            if (a.bindings) |b| heap.gpa.free(b[0..a.binding_capacity]);
            a.bindings = null;
            a.binding_count = 0;
            a.binding_capacity = 0;
        }
    }
    s.action_count = 0;
}

/// Compares the whole given name with each stored name, and returns -1 when none matches. A name
/// longer than `action_name_max` was stored truncated, so only its truncated form matches.
fn findActionByName(s: *const State, name: []const u8) i32 {
    const actions = s.actions orelse return -1;
    for (actions[0..s.action_count], 0..) |*a, i| {
        if (std.mem.eql(u8, std.mem.sliceTo(&a.name, 0), name)) return @intCast(i);
    }
    return -1;
}

fn copyName(dst: []u8, src: []const u8) void {
    const n = @min(src.len, dst.len - 1);
    @memcpy(dst[0..n], src[0..n]);
    dst[n] = 0;
}

/// A code outside the bits the snapshot carries, including `KE_KEY_UNKNOWN`, is never reported
/// held.
fn isKeyDown(snap: *const abi_input.c.ke_input_snapshot, key: c_int) bool {
    if (key < 0 or key >= key_bit_count) return false;
    const k: usize = @intCast(key);
    return (snap.keys_down[k / 64] >> @intCast(k % 64)) & 1 != 0;
}

/// A negative button, which is what an unknown mouse button name gives, is never reported held.
fn isMouseDown(snap: *const abi_input.c.ke_input_snapshot, button: c_int) bool {
    if (button < 0) return false;
    return (snap.mouse_buttons_down >> @intCast(button)) & 1 != 0;
}

fn axisOf(down: bool) f32 {
    return if (down) 1.0 else 0.0;
}

const Sample = struct { x: f32 = 0, y: f32 = 0, z: f32 = 0 };

/// The flag is the activity `vtEvaluate` acts on, and it is set when a component is nonzero. A quad
/// whose opposite keys are both held cancels to zero on that axis, so a binding whose keys cancel
/// out is inactive.
fn sampleBinding(b: *const Binding, snap: *const abi_input.c.ke_input_snapshot) struct { Sample, bool } {
    var out: Sample = .{};
    switch (b.kind) {
        .key => out.x = axisOf(isKeyDown(snap, b.k0)),
        .mouse_button => out.x = axisOf(isMouseDown(snap, b.k0)),
        .key_pair => out.x = axisOf(isKeyDown(snap, b.k1)) - axisOf(isKeyDown(snap, b.k0)),
        .key_quad => {
            const up = axisOf(isKeyDown(snap, b.k0));
            const down = axisOf(isKeyDown(snap, b.k1));
            const left = axisOf(isKeyDown(snap, b.k2));
            const right = axisOf(isKeyDown(snap, b.k3));
            out.x = right - left;
            out.y = up - down;
        },
    }
    return .{ out, out.x != 0.0 or out.y != 0.0 or out.z != 0.0 };
}

/// Releases the string that the TOML string lookup allocated for a found value. A lookup that did
/// not find its key allocates nothing, so there is nothing to release.
fn freeDatumStr(d: c.toml_datum_t) void {
    if (d.ok != 0 and d.u.s != null) std.c.free(d.u.s);
}

/// Writes `out` only when it returns true. It returns false when the table has no "kind" string,
/// when the kind is not one it knows, or when a field that kind needs is missing.
/// Why a binding table could not be read, written by `parseBindingTable`.
const Reason = struct {
    buf: [160]u8 = undefined,
    len: usize = 0,

    fn set(self: *Reason, comptime fmt: []const u8, args: anytype) void {
        self.len = if (std.fmt.bufPrint(&self.buf, fmt, args)) |m| m.len else |_| self.buf.len;
    }

    fn text(self: *const Reason) []const u8 {
        return self.buf[0..self.len];
    }
};

fn keyCode(name: [*c]const u8, reason: *Reason) ?c_int {
    const code = lookupKey(name);
    if (code >= 0) return code;
    reason.set("'{s}' is not a key name", .{std.mem.span(name)});
    return null;
}

fn mouseCode(name: [*c]const u8, reason: *Reason) ?c_int {
    const code = lookupMouseButton(name);
    if (code >= 0) return code;
    reason.set("'{s}' is not a mouse button name", .{std.mem.span(name)});
    return null;
}

/// Reads one binding table into `out`. A missing field, an unknown kind, or a name that is no key
/// or mouse button returns false with the reason in `reason`.
fn parseBindingTable(bt: ?*c.toml_table_t, out: *Binding, reason: *Reason) bool {
    const kind = c.toml_string_in(bt, "kind");
    if (kind.ok == 0) {
        reason.set("it has no kind", .{});
        return false;
    }
    defer freeDatumStr(kind);
    const kind_str = std.mem.span(kind.u.s);

    if (std.mem.eql(u8, kind_str, "key")) {
        const k = c.toml_string_in(bt, "key");
        defer freeDatumStr(k);
        if (k.ok == 0) {
            reason.set("a key binding has no key", .{});
            return false;
        }
        out.* = .{ .kind = .key, .k0 = keyCode(k.u.s, reason) orelse return false };
        return true;
    }
    if (std.mem.eql(u8, kind_str, "key_pair")) {
        const neg = c.toml_string_in(bt, "negative");
        const pos = c.toml_string_in(bt, "positive");
        defer freeDatumStr(neg);
        defer freeDatumStr(pos);
        if (neg.ok == 0 or pos.ok == 0) {
            reason.set("a key_pair binding needs negative and positive", .{});
            return false;
        }
        out.* = .{
            .kind = .key_pair,
            .k0 = keyCode(neg.u.s, reason) orelse return false,
            .k1 = keyCode(pos.u.s, reason) orelse return false,
        };
        return true;
    }
    if (std.mem.eql(u8, kind_str, "key_quad")) {
        const up = c.toml_string_in(bt, "up");
        const down = c.toml_string_in(bt, "down");
        const left = c.toml_string_in(bt, "left");
        const right = c.toml_string_in(bt, "right");
        defer freeDatumStr(up);
        defer freeDatumStr(down);
        defer freeDatumStr(left);
        defer freeDatumStr(right);
        if (up.ok == 0 or down.ok == 0 or left.ok == 0 or right.ok == 0) {
            reason.set("a key_quad binding needs up, down, left and right", .{});
            return false;
        }
        out.* = .{
            .kind = .key_quad,
            .k0 = keyCode(up.u.s, reason) orelse return false,
            .k1 = keyCode(down.u.s, reason) orelse return false,
            .k2 = keyCode(left.u.s, reason) orelse return false,
            .k3 = keyCode(right.u.s, reason) orelse return false,
        };
        return true;
    }
    if (std.mem.eql(u8, kind_str, "mouse")) {
        const btn = c.toml_string_in(bt, "button");
        defer freeDatumStr(btn);
        if (btn.ok == 0) {
            reason.set("a mouse binding has no button", .{});
            return false;
        }
        out.* = .{ .kind = .mouse_button, .k0 = mouseCode(btn.u.s, reason) orelse return false };
        return true;
    }
    reason.set("'{s}' is not a binding kind", .{kind_str});
    return false;
}

/// Drops every action, the one being read included, so a load that fails leaves none, and returns
/// `err` for the caller to return.
fn abandonLoad(s: *State, err: R.Error) R.Error {
    s.action_count += 1;
    clearActions(s);
    return err;
}

/// Slot `load`. Replaces the whole set of actions from a TOML file, reading each binding table
/// with `parseBindingTable`. It clears all actions before
/// reading, and a load that fails leaves no actions. Ids handed out before a load are not valid after it. It reports not found when the
/// file cannot be opened, an I/O error when the text does not parse, and out of memory when an
/// action or a binding cannot be allocated, and an invalid argument for a null handle or path, for
/// an action type that is not Button, Axis1D, Axis2D or Axis3D, and for a binding that cannot be
/// read, naming the action, the binding and why.
/// A file without an "action" table succeeds with no actions.
fn vtLoad(
    self_in: ?*abi_input_actions.c.ke_input_actions,
    path: [*c]const u8,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null or path == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    clearActions(s);
    return R.of(load(s, path));
}

fn load(s: *State, path: [*c]const u8) R.Error!void {
    const text = file_read.readText(s.io, path) catch |err| {
        log.warn("input file '{s}' could not be read: {t}", .{ path, err });
        return err;
    };
    defer heap.gpa.free(text);
    var errbuf: [200]u8 = undefined;
    const root = c.toml_parse(text.ptr, &errbuf, errbuf.len);
    if (root == null) {
        log.warn("input file '{s}' does not parse: {s}", .{ path, std.mem.sliceTo(&errbuf, 0) });
        return error.Io;
    }
    defer c.toml_free(root);

    const action_section = c.toml_table_in(root, "action") orelse return;

    var i: c_int = 0;
    while (true) : (i += 1) {
        const action_name = c.toml_key_in(action_section, i) orelse break;
        const action_tbl = c.toml_table_in(action_section, action_name) orelse continue;

        if (!ensureActionCapacity(s, s.action_count + 1)) return error.OutOfMemory;
        const act = &s.actions.?[s.action_count];
        act.* = Action.blank();
        copyName(&act.name, std.mem.span(action_name));

        const type_node = c.toml_string_in(action_tbl, "type");
        if (type_node.ok != 0) {
            defer freeDatumStr(type_node);
            act.type = parseActionType(type_node.u.s) orelse {
                log.warn("action '{s}': '{s}' is not an action type", .{ std.mem.span(action_name), std.mem.span(type_node.u.s) });
                return abandonLoad(s, error.InvalidArgument);
            };
        }

        if (c.toml_array_in(action_tbl, "bindings")) |bindings_arr| {
            const n = c.toml_array_nelem(bindings_arr);
            var j: c_int = 0;
            while (j < n) : (j += 1) {
                const bt = c.toml_table_at(bindings_arr, j) orelse continue;
                var b: Binding = undefined;
                var reason: Reason = .{};
                if (!parseBindingTable(bt, &b, &reason)) {
                    log.warn("action '{s}', binding {d}: {s}", .{ std.mem.span(action_name), j + 1, reason.text() });
                    return abandonLoad(s, error.InvalidArgument);
                }
                if (!ensureBindingCapacity(act, act.binding_count + 1)) return abandonLoad(s, error.OutOfMemory);
                act.bindings.?[act.binding_count] = b;
                act.binding_count += 1;
            }
        }

        s.action_count += 1;
    }
}

/// Slot `get_action_id`. Returns the id of the action with that name, or -1 for a null handle or
/// name and for a name no action has; it sets no error.
fn vtGetActionId(self_in: ?*abi_input_actions.c.ke_input_actions, name: [*c]const u8) callconv(.c) i32 {
    const self = self_in orelse return -1;
    if (self.handle == null or name == null) return -1;
    return findActionByName(stateOf(self), std.mem.span(name));
}

/// Slot `add_action`. Appends the action after those already present, so earlier ids keep their
/// meaning. Returns -1
/// for a null or empty name, for a name already present, and when the array cannot grow. Each of
/// those leaves the actions unchanged, and none of them sets an error.
fn vtAddAction(
    self_in: ?*abi_input_actions.c.ke_input_actions,
    name: [*c]const u8,
    action_type: abi_input_actions.c.ke_action_type,
) callconv(.c) i32 {
    const self = self_in orelse return -1;
    if (self.handle == null or name == null or name[0] == 0) return -1;
    const s = stateOf(self);
    const n = std.mem.span(name);
    if (findActionByName(s, n) >= 0) return -1;
    if (!ensureActionCapacity(s, s.action_count + 1)) return -1;

    const act = &s.actions.?[s.action_count];
    act.* = Action.blank();
    copyName(&act.name, n);
    act.type = action_type;
    const id: i32 = @intCast(s.action_count);
    s.action_count += 1;
    return id;
}

/// The pointer addresses an element of the action array, so it is valid only until that array
/// grows.
fn getActionMut(s: *State, id: i32) ?*Action {
    if (id < 0 or @as(u32, @intCast(id)) >= s.action_count) return null;
    return &s.actions.?[@intCast(id)];
}

/// Appends one binding to the action with the given id. It reports not found when no action has
/// that id, and out of memory when the bindings cannot grow. The action is unchanged in both cases.
fn appendBinding(s: *State, id: i32, b: Binding) abi_result.c.ke_result {
    const a = getActionMut(s, id) orelse return R.code(error.NotFound);
    if (!ensureBindingCapacity(a, a.binding_count + 1)) return R.code(error.OutOfMemory);
    a.bindings.?[a.binding_count] = b;
    a.binding_count += 1;
    return R.ok;
}

/// Slot `bind_key`. Stores the key code as given. A code the snapshot cannot carry is not refused
/// here, and it is never reported as held. A null handle is an invalid argument, an id that names
/// no action is not found, and a binding array that cannot grow is out of memory.
fn vtBindKey(
    self_in: ?*abi_input_actions.c.ke_input_actions,
    action_id: i32,
    key: abi_input.c.ke_key,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null) return R.code(error.InvalidArgument);
    return appendBinding(stateOf(self), action_id, .{ .kind = .key, .k0 = @intCast(key) });
}

/// Slot `bind_mouse_button`. Failures are those of `vtBindKey`.
fn vtBindMouseButton(
    self_in: ?*abi_input_actions.c.ke_input_actions,
    action_id: i32,
    button: abi_input.c.ke_mouse_button,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null) return R.code(error.InvalidArgument);
    return appendBinding(stateOf(self), action_id, .{ .kind = .mouse_button, .k0 = @intCast(button) });
}

/// Slot `bind_key_pair`. The pair reads one axis, positive when `pos` is held and negative when
/// `neg` is. Failures are those of `vtBindKey`.
fn vtBindKeyPair(
    self_in: ?*abi_input_actions.c.ke_input_actions,
    action_id: i32,
    neg: abi_input.c.ke_key,
    pos: abi_input.c.ke_key,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null) return R.code(error.InvalidArgument);
    return appendBinding(
        stateOf(self),
        action_id,
        .{ .kind = .key_pair, .k0 = @intCast(neg), .k1 = @intCast(pos) },
    );
}

/// Slot `bind_key_quad`. The quad reads two axes: x is right minus left and y is up minus down.
/// Failures are those of `vtBindKey`.
fn vtBindKeyQuad(
    self_in: ?*abi_input_actions.c.ke_input_actions,
    action_id: i32,
    up: abi_input.c.ke_key,
    down: abi_input.c.ke_key,
    left: abi_input.c.ke_key,
    right: abi_input.c.ke_key,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null) return R.code(error.InvalidArgument);
    return appendBinding(stateOf(self), action_id, .{
        .kind = .key_quad,
        .k0 = @intCast(up),
        .k1 = @intCast(down),
        .k2 = @intCast(left),
        .k3 = @intCast(right),
    });
}

/// Slot `evaluate`. Runs one frame: it samples the snapshot into the action values and reports the
/// transitions through the event callback, synchronously and on the calling thread. A button
/// action is active when any binding is, and an axis action takes the largest magnitude per
/// component. The callback gets started and canceled on a change of activity, and performed for
/// an axis that moved while held. An action's callback sees its own new state, while actions
/// later in the order still hold the previous frame's values. A null handle or a null snapshot
/// reports invalid argument and changes nothing.
fn vtEvaluate(
    self_in: ?*abi_input_actions.c.ke_input_actions,
    snapshot_in: ?*const abi_input.c.ke_input_snapshot,
    on_event: abi_input_actions.c.ke_input_action_event_func,
    event_ctx: ?*anyopaque,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    const snapshot = snapshot_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    if (s.action_count == 0) return R.ok;

    for (s.actions.?[0..s.action_count], 0..) |*a, idx| {
        a.prev_active = a.curr_active;
        a.prev_x = a.curr_x;
        a.prev_y = a.curr_y;
        a.prev_z = a.curr_z;

        var acc: Sample = .{};
        var any_active = false;
        if (a.bindings) |bindings| {
            for (bindings[0..a.binding_count]) |*b| {
                const sampled, const active = sampleBinding(b, snapshot);
                if (!active) continue;
                any_active = true;
                if (a.type == abi_input_actions.c.KE_ACTION_TYPE_BUTTON) {
                    acc.x = 1.0;
                } else {
                    if (@abs(sampled.x) > @abs(acc.x)) acc.x = sampled.x;
                    if (@abs(sampled.y) > @abs(acc.y)) acc.y = sampled.y;
                    if (@abs(sampled.z) > @abs(acc.z)) acc.z = sampled.z;
                }
            }
        }
        a.curr_x = acc.x;
        a.curr_y = acc.y;
        a.curr_z = acc.z;
        a.curr_active = any_active;

        const emit = on_event orelse continue;
        const id: i32 = @intCast(idx);

        if (a.curr_active != a.prev_active) {
            var ev = std.mem.zeroes(abi_input_actions.c.ke_input_action_event);
            ev.action_id = id;
            ev.type = a.type;
            ev.phase = if (a.curr_active) abi_input_actions.c.KE_ACTION_PHASE_STARTED else abi_input_actions.c.KE_ACTION_PHASE_CANCELED;
            ev.x = acc.x;
            ev.y = acc.y;
            ev.z = acc.z;
            emit(event_ctx, ev);
        }
        if (a.curr_active and a.prev_active and
            a.type != abi_input_actions.c.KE_ACTION_TYPE_BUTTON and
            (a.prev_x != a.curr_x or a.prev_y != a.curr_y or a.prev_z != a.curr_z))
        {
            var ev = std.mem.zeroes(abi_input_actions.c.ke_input_action_event);
            ev.action_id = id;
            ev.type = a.type;
            ev.phase = abi_input_actions.c.KE_ACTION_PHASE_PERFORMED;
            ev.x = acc.x;
            ev.y = acc.y;
            ev.z = acc.z;
            emit(event_ctx, ev);
        }
    }
    return R.ok;
}

/// Returns a pointer into the action array, valid until the next add or load, or null for a null
/// handle or an id that names no action.
fn getAction(self_in: ?*abi_input_actions.c.ke_input_actions, id: i32) ?*const Action {
    const self = self_in orelse return null;
    if (self.handle == null) return null;
    const s = stateOf(self);
    if (id < 0 or @as(u32, @intCast(id)) >= s.action_count) return null;
    return &s.actions.?[@intCast(id)];
}

/// Slot `is_action_down`. True while the action is active as of the last evaluation; false for an
/// unknown id.
fn vtIsActionDown(self_in: ?*abi_input_actions.c.ke_input_actions, id: i32) callconv(.c) bool {
    const a = getAction(self_in, id) orelse return false;
    return a.curr_active;
}

/// Slot `was_action_pressed`. True when the last evaluation made the action active; false for an
/// unknown id.
fn vtWasActionPressed(self_in: ?*abi_input_actions.c.ke_input_actions, id: i32) callconv(.c) bool {
    const a = getAction(self_in, id) orelse return false;
    if (a.curr_active and !a.prev_active) return true;
    return false;
}

/// Slot `was_action_released`. True when the last evaluation made the action inactive; false for
/// an unknown id.
fn vtWasActionReleased(self_in: ?*abi_input_actions.c.ke_input_actions, id: i32) callconv(.c) bool {
    const a = getAction(self_in, id) orelse return false;
    if (!a.curr_active and a.prev_active) return true;
    return false;
}

/// Slot `get_axis1d`. Returns the stored x value; zero for an unknown id.
fn vtGetAxis1d(self_in: ?*abi_input_actions.c.ke_input_actions, id: i32) callconv(.c) f32 {
    const a = getAction(self_in, id) orelse return 0.0;
    return a.curr_x;
}

/// Slot `get_axis2d`. Writes the stored x and y values to the non-null outputs; zero for an
/// unknown id.
fn vtGetAxis2d(self_in: ?*abi_input_actions.c.ke_input_actions, id: i32, out_x: [*c]f32, out_y: [*c]f32) callconv(.c) void {
    const a = getAction(self_in, id);
    if (out_x != null) out_x.* = if (a) |act| act.curr_x else 0.0;
    if (out_y != null) out_y.* = if (a) |act| act.curr_y else 0.0;
}

/// Slot `get_axis3d`. Writes the stored x, y and z values to the non-null outputs; zero for an
/// unknown id.
fn vtGetAxis3d(
    self_in: ?*abi_input_actions.c.ke_input_actions,
    id: i32,
    out_x: [*c]f32,
    out_y: [*c]f32,
    out_z: [*c]f32,
) callconv(.c) void {
    const a = getAction(self_in, id);
    if (out_x != null) out_x.* = if (a) |act| act.curr_x else 0.0;
    if (out_y != null) out_y.* = if (a) |act| act.curr_y else 0.0;
    if (out_z != null) out_z.* = if (a) |act| act.curr_z else 0.0;
}

/// The destroy of the handle. Frees the bindings, the action array and the `State`. The `api` that
/// the handle's ref pointed at is invalid afterwards.
fn vtDestroy(self_in: ?*abi_input_actions.c.ke_input_actions) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    clearActions(s);
    if (s.actions) |actions| heap.gpa.free(actions[0..s.action_capacity]);
    heap.gpa.destroy(s);
}

/// Factory. Writes a handle to an empty map, which reads its file through `io_in`. A null out-parameter fails as an invalid argument and
/// an allocation failure as out of memory, leaving the handle zeroed.
export fn ke_input_actions_create(io_in: ?*abi_io.c.ke_io, out_actions: ?*abi_input_actions.c.ke_input_actions_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_actions orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_input_actions.c.ke_input_actions_handle);
    const io = io_in orelse return R.code(error.InvalidArgument);

    const s = heap.gpa.create(State) catch |err| return R.code(err);
    s.* = .{ .api = std.mem.zeroes(abi_input_actions.c.ke_input_actions), .actions = null, .action_count = 0, .action_capacity = 0, .io = io };

    s.api.handle = s;
    s.api.load = vtLoad;
    s.api.get_action_id = vtGetActionId;
    s.api.add_action = vtAddAction;
    s.api.bind_key = vtBindKey;
    s.api.bind_mouse_button = vtBindMouseButton;
    s.api.bind_key_pair = vtBindKeyPair;
    s.api.bind_key_quad = vtBindKeyQuad;
    s.api.evaluate = vtEvaluate;
    s.api.is_action_down = vtIsActionDown;
    s.api.was_action_pressed = vtWasActionPressed;
    s.api.was_action_released = vtWasActionReleased;
    s.api.get_axis1d = vtGetAxis1d;
    s.api.get_axis2d = vtGetAxis2d;
    s.api.get_axis3d = vtGetAxis3d;

    out.* = .{ .ref = &s.api, .destroy = vtDestroy };
    return R.ok;
}

const testing = std.testing;
const served_files = @import("served_files_test.zig");

const TempInput = struct {
    tmp: served_files.Dir,
    path_buf: [std.fs.max_path_bytes]u8,

    fn init(contents: []const u8) !TempInput {
        var self = TempInput{
            .tmp = served_files.Dir.init(),
            .path_buf = undefined,
        };
        errdefer self.tmp.cleanup();

        const name = "bindings.input";
        try self.tmp.writeFile(name, contents);

        const full = try std.fmt.bufPrint(&self.path_buf, "{s}/{s}", .{ self.tmp.path(), name });
        self.path_buf[full.len] = 0;
        return self;
    }

    fn cPath(self: *const TempInput) [*:0]const u8 {
        return @ptrCast(&self.path_buf);
    }

    fn deinit(self: *TempInput) void {
        self.tmp.cleanup();
    }
};

const Actions = struct {
    handle: abi_input_actions.c.ke_input_actions_handle,

    fn init() !Actions {
        var h = std.mem.zeroes(abi_input_actions.c.ke_input_actions_handle);
        try testing.expectEqual(R.ok, ke_input_actions_create(served_files.io(), &h));
        return .{ .handle = h };
    }

    fn api(self: *const Actions) *abi_input_actions.c.ke_input_actions {
        return @ptrCast(self.handle.ref);
    }

    fn deinit(self: *Actions) void {
        self.handle.destroy.?(self.handle.ref);
    }
};

fn pressKey(snapshot: *abi_input.c.ke_input_snapshot, key: c_int) void {
    const index: usize = @intCast(@divFloor(key, 64));
    const bit: u6 = @intCast(@mod(key, 64));
    snapshot.keys_down[index] |= (@as(u64, 1) << bit);
}

const PhaseCounter = struct {
    started: i32 = 0,
    performed: i32 = 0,
    canceled: i32 = 0,
};

fn countPhase(ctx: ?*anyopaque, event: abi_input_actions.c.ke_input_action_event) callconv(.c) void {
    const counter: *PhaseCounter = @ptrCast(@alignCast(ctx.?));
    switch (event.phase) {
        abi_input_actions.c.KE_ACTION_PHASE_STARTED => counter.started += 1,
        abi_input_actions.c.KE_ACTION_PHASE_PERFORMED => counter.performed += 1,
        abi_input_actions.c.KE_ACTION_PHASE_CANCELED => counter.canceled += 1,
        else => {},
    }
}

test "creating the actions map yields a usable handle" {
    var a = try Actions.init();
    defer a.deinit();

    try testing.expect(a.api().handle != null);
    try testing.expect(a.handle.destroy != null);
}

test "loading a file that is not there fails" {
    var a = try Actions.init();
    defer a.deinit();

    try testing.expectEqual(R.code(error.NotFound), a.api().load.?(a.api(), "does/not/exist.input"));
}

test "actions are numbered in the order the file declares them" {
    var file = try TempInput.init(
        \\[action.Jump]
        \\type = "Button"
        \\bindings = [ { kind = "key", key = "Space" } ]
        \\
        \\[action.Move]
        \\type = "Axis1D"
        \\bindings = [ { kind = "key_pair", negative = "S", positive = "W" } ]
        \\
    );
    defer file.deinit();

    var a = try Actions.init();
    defer a.deinit();

    try testing.expectEqual(R.ok, a.api().load.?(a.api(), file.cPath()));
    try testing.expectEqual(@as(i32, 0), a.api().get_action_id.?(a.api(), "Jump"));
    try testing.expectEqual(@as(i32, 1), a.api().get_action_id.?(a.api(), "Move"));
    try testing.expectEqual(@as(i32, -1), a.api().get_action_id.?(a.api(), "Unknown"));
}

test "a bound key reports pressed on the edge and down while it is held" {
    var file = try TempInput.init(
        \\[action.Jump]
        \\type = "Button"
        \\bindings = [ { kind = "key", key = "Space" } ]
        \\
    );
    defer file.deinit();

    var a = try Actions.init();
    defer a.deinit();
    try testing.expectEqual(R.ok, a.api().load.?(a.api(), file.cPath()));
    const id = a.api().get_action_id.?(a.api(), "Jump");

    var snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);
    _ = a.api().evaluate.?(a.api(), &snapshot, null, null);
    try testing.expect(!a.api().is_action_down.?(a.api(), id));
    try testing.expect(!a.api().was_action_pressed.?(a.api(), id));

    pressKey(&snapshot, abi_input.c.KE_KEY_SPACE);
    _ = a.api().evaluate.?(a.api(), &snapshot, null, null);
    try testing.expect(a.api().is_action_down.?(a.api(), id));
    try testing.expect(a.api().was_action_pressed.?(a.api(), id));

    _ = a.api().evaluate.?(a.api(), &snapshot, null, null);
    try testing.expect(a.api().is_action_down.?(a.api(), id));
    try testing.expect(!a.api().was_action_pressed.?(a.api(), id));

    snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);
    _ = a.api().evaluate.?(a.api(), &snapshot, null, null);
    try testing.expect(!a.api().is_action_down.?(a.api(), id));
    try testing.expect(a.api().was_action_released.?(a.api(), id));
}

test "a key pair reads one at each end and cancels when both are held" {
    var file = try TempInput.init(
        \\[action.Move]
        \\type = "Axis1D"
        \\bindings = [ { kind = "key_pair", negative = "S", positive = "W" } ]
        \\
    );
    defer file.deinit();

    var a = try Actions.init();
    defer a.deinit();
    try testing.expectEqual(R.ok, a.api().load.?(a.api(), file.cPath()));
    const id = a.api().get_action_id.?(a.api(), "Move");

    var snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);
    pressKey(&snapshot, abi_input.c.KE_KEY_W);
    _ = a.api().evaluate.?(a.api(), &snapshot, null, null);
    try testing.expectEqual(@as(f32, 1.0), a.api().get_axis1d.?(a.api(), id));

    snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);
    pressKey(&snapshot, abi_input.c.KE_KEY_S);
    _ = a.api().evaluate.?(a.api(), &snapshot, null, null);
    try testing.expectEqual(@as(f32, -1.0), a.api().get_axis1d.?(a.api(), id));

    snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);
    pressKey(&snapshot, abi_input.c.KE_KEY_W);
    pressKey(&snapshot, abi_input.c.KE_KEY_S);
    _ = a.api().evaluate.?(a.api(), &snapshot, null, null);
    try testing.expectEqual(@as(f32, 0.0), a.api().get_axis1d.?(a.api(), id));
}

test "a key quad drives both axes at once" {
    var file = try TempInput.init(
        \\[action.Move]
        \\type = "Axis2D"
        \\bindings = [ { kind = "key_quad", up = "W", down = "S", left = "A", right = "D" } ]
        \\
    );
    defer file.deinit();

    var a = try Actions.init();
    defer a.deinit();
    try testing.expectEqual(R.ok, a.api().load.?(a.api(), file.cPath()));
    const id = a.api().get_action_id.?(a.api(), "Move");

    var snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);
    pressKey(&snapshot, abi_input.c.KE_KEY_W);
    pressKey(&snapshot, abi_input.c.KE_KEY_D);
    _ = a.api().evaluate.?(a.api(), &snapshot, null, null);

    var x: f32 = 0;
    var y: f32 = 0;
    a.api().get_axis2d.?(a.api(), id, &x, &y);
    try testing.expectEqual(@as(f32, 1.0), x);
    try testing.expectEqual(@as(f32, 1.0), y);
}

test "a mouse binding read from a file drives a button action" {
    var file = try TempInput.init(
        \\[action.Fire]
        \\type = "Button"
        \\bindings = [ { kind = "mouse", button = "Left" } ]
        \\
    );
    defer file.deinit();

    var a = try Actions.init();
    defer a.deinit();
    try testing.expectEqual(R.ok, a.api().load.?(a.api(), file.cPath()));
    const id = a.api().get_action_id.?(a.api(), "Fire");

    var snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);
    snapshot.mouse_buttons_down = @as(u32, 1) << @intCast(abi_input.c.KE_MOUSE_BUTTON_LEFT);
    _ = a.api().evaluate.?(a.api(), &snapshot, null, null);
    try testing.expect(a.api().is_action_down.?(a.api(), id));
}

test "an action starts once on the edge and cancels when the key goes up" {
    var file = try TempInput.init(
        \\[action.Jump]
        \\type = "Button"
        \\bindings = [ { kind = "key", key = "Space" } ]
        \\
    );
    defer file.deinit();

    var a = try Actions.init();
    defer a.deinit();
    try testing.expectEqual(R.ok, a.api().load.?(a.api(), file.cPath()));

    var counter = PhaseCounter{};
    var snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);

    _ = a.api().evaluate.?(a.api(), &snapshot, countPhase, &counter);
    try testing.expectEqual(@as(i32, 0), counter.started);

    pressKey(&snapshot, abi_input.c.KE_KEY_SPACE);
    _ = a.api().evaluate.?(a.api(), &snapshot, countPhase, &counter);
    try testing.expectEqual(@as(i32, 1), counter.started);
    try testing.expectEqual(@as(i32, 0), counter.performed);

    _ = a.api().evaluate.?(a.api(), &snapshot, countPhase, &counter);
    try testing.expectEqual(@as(i32, 1), counter.started);
    try testing.expectEqual(@as(i32, 0), counter.performed);

    snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);
    _ = a.api().evaluate.?(a.api(), &snapshot, countPhase, &counter);
    try testing.expectEqual(@as(i32, 1), counter.canceled);
}

fn expectLoadRefused(text: []const u8) !void {
    var file = try TempInput.init(text);
    defer file.deinit();
    var a = try Actions.init();
    defer a.deinit();
    try testing.expectEqual(R.code(error.InvalidArgument), a.api().load.?(a.api(), file.cPath()));
}

test "a misspelt key name fails the load as an invalid argument" {
    try expectLoadRefused(
        \\[action.Jump]
        \\bindings = [ { kind = "key", key = "Space" }, { kind = "key", key = "Spcae" } ]
        \\
    );
}

test "an unknown mouse button, binding kind or action type fails the load" {
    try expectLoadRefused(
        \\[action.Fire]
        \\bindings = [ { kind = "mouse", button = "Thumb" } ]
        \\
    );
    try expectLoadRefused(
        \\[action.Fire]
        \\bindings = [ { kind = "pad", button = "A" } ]
        \\
    );
    try expectLoadRefused(
        \\[action.Move]
        \\type = "Axis1d"
        \\
    );
}

test "a binding missing a field fails the load" {
    try expectLoadRefused(
        \\[action.Move]
        \\bindings = [ { kind = "key_pair", negative = "A" } ]
        \\
    );
}

test "actions added by hand are numbered in the order they arrive" {
    var a = try Actions.init();
    defer a.deinit();

    try testing.expectEqual(@as(i32, 0), a.api().add_action.?(a.api(), "Jump", abi_input_actions.c.KE_ACTION_TYPE_BUTTON));
    try testing.expectEqual(@as(i32, 1), a.api().add_action.?(a.api(), "Move", abi_input_actions.c.KE_ACTION_TYPE_AXIS2D));
    try testing.expectEqual(@as(i32, 2), a.api().add_action.?(a.api(), "Look", abi_input_actions.c.KE_ACTION_TYPE_AXIS2D));

    try testing.expectEqual(@as(i32, 0), a.api().get_action_id.?(a.api(), "Jump"));
    try testing.expectEqual(@as(i32, 1), a.api().get_action_id.?(a.api(), "Move"));
    try testing.expectEqual(@as(i32, 2), a.api().get_action_id.?(a.api(), "Look"));
}

test "a duplicated, empty or absent action name is refused" {
    var a = try Actions.init();
    defer a.deinit();

    try testing.expectEqual(@as(i32, 0), a.api().add_action.?(a.api(), "Jump", abi_input_actions.c.KE_ACTION_TYPE_BUTTON));
    try testing.expectEqual(@as(i32, -1), a.api().add_action.?(a.api(), "Jump", abi_input_actions.c.KE_ACTION_TYPE_BUTTON));
    try testing.expectEqual(@as(i32, -1), a.api().add_action.?(a.api(), "", abi_input_actions.c.KE_ACTION_TYPE_BUTTON));
    try testing.expectEqual(@as(i32, -1), a.api().add_action.?(a.api(), null, abi_input_actions.c.KE_ACTION_TYPE_BUTTON));
}

test "a key bound by hand drives its button" {
    var a = try Actions.init();
    defer a.deinit();

    const id = a.api().add_action.?(a.api(), "Jump", abi_input_actions.c.KE_ACTION_TYPE_BUTTON);
    try testing.expectEqual(R.ok, a.api().bind_key.?(a.api(), id, abi_input.c.KE_KEY_SPACE));

    var snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);
    pressKey(&snapshot, abi_input.c.KE_KEY_SPACE);
    try testing.expectEqual(R.ok, a.api().evaluate.?(a.api(), &snapshot, null, null));
    try testing.expect(a.api().is_action_down.?(a.api(), id));
    try testing.expect(a.api().was_action_pressed.?(a.api(), id));
}

test "a key pair bound by hand produces a one dimensional axis" {
    var a = try Actions.init();
    defer a.deinit();

    const id = a.api().add_action.?(a.api(), "Strafe", abi_input_actions.c.KE_ACTION_TYPE_AXIS1D);
    try testing.expectEqual(R.ok, a.api().bind_key_pair.?(a.api(), id, abi_input.c.KE_KEY_A, abi_input.c.KE_KEY_D));

    var snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);
    pressKey(&snapshot, abi_input.c.KE_KEY_D);
    try testing.expectEqual(R.ok, a.api().evaluate.?(a.api(), &snapshot, null, null));
    try testing.expectEqual(@as(f32, 1.0), a.api().get_axis1d.?(a.api(), id));

    snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);
    pressKey(&snapshot, abi_input.c.KE_KEY_A);
    try testing.expectEqual(R.ok, a.api().evaluate.?(a.api(), &snapshot, null, null));
    try testing.expectEqual(@as(f32, -1.0), a.api().get_axis1d.?(a.api(), id));
}

test "a key quad bound by hand produces a two dimensional axis" {
    var a = try Actions.init();
    defer a.deinit();

    const id = a.api().add_action.?(a.api(), "Move", abi_input_actions.c.KE_ACTION_TYPE_AXIS2D);
    try testing.expectEqual(R.ok, a.api().bind_key_quad.?(a.api(), id, abi_input.c.KE_KEY_W, abi_input.c.KE_KEY_S, abi_input.c.KE_KEY_A, abi_input.c.KE_KEY_D));

    var snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);
    pressKey(&snapshot, abi_input.c.KE_KEY_W);
    pressKey(&snapshot, abi_input.c.KE_KEY_D);
    try testing.expectEqual(R.ok, a.api().evaluate.?(a.api(), &snapshot, null, null));

    var x: f32 = 0;
    var y: f32 = 0;
    a.api().get_axis2d.?(a.api(), id, &x, &y);
    try testing.expectEqual(@as(f32, 1.0), x);
    try testing.expectEqual(@as(f32, 1.0), y);
}

test "a mouse button bound by hand drives its action" {
    var a = try Actions.init();
    defer a.deinit();

    const id = a.api().add_action.?(a.api(), "Fire", abi_input_actions.c.KE_ACTION_TYPE_BUTTON);
    try testing.expectEqual(R.ok, a.api().bind_mouse_button.?(a.api(), id, abi_input.c.KE_MOUSE_BUTTON_LEFT));

    var snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);
    snapshot.mouse_buttons_down = @as(u32, 1) << @intCast(abi_input.c.KE_MOUSE_BUTTON_LEFT);
    try testing.expectEqual(R.ok, a.api().evaluate.?(a.api(), &snapshot, null, null));
    try testing.expect(a.api().is_action_down.?(a.api(), id));
}

test "binding onto an action id that was never added fails" {
    var a = try Actions.init();
    defer a.deinit();

    try testing.expectEqual(R.code(error.NotFound), a.api().bind_key.?(a.api(), 99, abi_input.c.KE_KEY_SPACE));
    try testing.expectEqual(R.code(error.NotFound), a.api().bind_key_pair.?(a.api(), 99, abi_input.c.KE_KEY_A, abi_input.c.KE_KEY_D));
}

test "a three dimensional axis starts at the origin" {
    var a = try Actions.init();
    defer a.deinit();

    const id = a.api().add_action.?(a.api(), "Move", abi_input_actions.c.KE_ACTION_TYPE_AXIS3D);
    var x: f32 = 1;
    var y: f32 = 1;
    var z: f32 = 1;
    a.api().get_axis3d.?(a.api(), id, &x, &y, &z);
    try testing.expectEqual(@as(f32, 0.0), x);
    try testing.expectEqual(@as(f32, 0.0), y);
    try testing.expectEqual(@as(f32, 0.0), z);
}

test "evaluating without a snapshot fails" {
    var a = try Actions.init();
    defer a.deinit();

    try testing.expectEqual(R.code(error.InvalidArgument), a.api().evaluate.?(a.api(), null, null, null));
}

test "a key held across two evaluations reports pressed only on the first" {
    var a = try Actions.init();
    defer a.deinit();

    const id = a.api().add_action.?(a.api(), "Jump", abi_input_actions.c.KE_ACTION_TYPE_BUTTON);
    try testing.expectEqual(R.ok, a.api().bind_key.?(a.api(), id, abi_input.c.KE_KEY_SPACE));

    var snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);
    pressKey(&snapshot, abi_input.c.KE_KEY_SPACE);
    _ = a.api().evaluate.?(a.api(), &snapshot, null, null);
    try testing.expect(a.api().was_action_pressed.?(a.api(), id));

    _ = a.api().evaluate.?(a.api(), &snapshot, null, null);
    try testing.expect(!a.api().was_action_pressed.?(a.api(), id));
}

test "creating and destroying the actions map leaves no block allocated" {
    var actions = try Actions.init();
    actions.deinit();
    try heap.expectNoLeaks();
}
