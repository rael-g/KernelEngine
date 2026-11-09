//! The input action maps: named actions grouped in prioritised maps, bound to keys and mouse
//! buttons, evaluated once per frame against an input snapshot and polled by a game; the factory
//! adds the maps a configuration describes through the same slots a program calls.

const abi_input_actions = @import("abi_input_actions");
const abi_framework_factory = @import("abi_framework_factory");
const abi_configuration = @import("abi_configuration");
const std = @import("std");

const abi_input = @import("abi_input");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const zsub = @import("zsub");
const heap = @import("heap");

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


const map_initial_capacity: u32 = 4;

/// One named action, held by value in the `actions` array of its `State`; `map` is the index of
/// the map it belongs to. `bindings` stays null until the first binding is appended. `vtEvaluate`
/// moves the current values to the previous ones before sampling, and the edge queries compare
/// `curr_active` with `prev_active`.
const Action = struct {
    name: [action_name_max]u8,
    map: u32,
    type: abi_input_actions.c.ke_action_type,
    bindings: ?[*]Binding,
    binding_count: u32,
    binding_capacity: u32,

    curr_x: f32,
    curr_y: f32,
    curr_z: f32,
    curr_active: bool,
    prev_active: bool,

    fn blank() Action {
        return .{
            .name = [_]u8{0} ** action_name_max,
            .map = 0,
            .type = abi_input_actions.c.KE_ACTION_TYPE_BUTTON,
            .bindings = null,
            .binding_count = 0,
            .binding_capacity = 0,
            .curr_x = 0,
            .curr_y = 0,
            .curr_z = 0,
            .curr_active = false,
            .prev_active = false,
        };
    }
};

/// One named map, held by value in the `maps` array of its `State`.
const Map = struct {
    name: [action_name_max]u8,
    priority: i32,
    enabled: bool,
};

/// The object behind the handle `ke_input_actions_create` returns, freed by `vtDestroy`; `api`
/// is the vtable the handle points at, and its `handle` points back here. A map id is an index
/// in `maps` and an action id an index in `actions`, so appending keeps every id valid.
/// `vtEvaluate` walks the maps from the highest priority down, masks out of the snapshot every key
/// and mouse button an earlier enabled map binds, samples each action of an enabled map against
/// the masked snapshot and clears the actions of a disabled one; the queries only read the stored
/// values. Nothing here locks, so one handle is not safe to use from several threads at once.
const State = struct {
    api: abi_input_actions.c.ke_input_actions,
    maps: ?[*]Map = null,
    map_count: u32 = 0,
    map_capacity: u32 = 0,
    actions: ?[*]Action = null,
    action_count: u32 = 0,
    action_capacity: u32 = 0,
    runtime: ?*abi_runtime.c.ke_runtime = null,
    input: ?*abi_input.c.ke_input = null,
    system: abi_runtime.c.ke_system_id = 0,
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

fn ensureMapCapacity(s: *State, needed: u32) bool {
    const grown = growArray(Map, s.maps, s.map_count, &s.map_capacity, needed, map_initial_capacity) orelse return false;
    s.maps = grown;
    return true;
}

fn ensureBindingCapacity(a: *Action, needed: u32) bool {
    const grown = growArray(Binding, a.bindings, a.binding_count, &a.binding_capacity, needed, binding_initial_capacity) orelse return false;
    a.bindings = grown;
    return true;
}

fn findActionByName(s: *const State, name: []const u8) i32 {
    const actions = s.actions orelse return -1;
    for (actions[0..s.action_count], 0..) |*a, i| {
        if (std.mem.eql(u8, std.mem.sliceTo(&a.name, 0), name)) return @intCast(i);
    }
    return -1;
}

fn findMapByName(s: *const State, name: []const u8) i32 {
    const maps = s.maps orelse return -1;
    for (maps[0..s.map_count], 0..) |*m, i| {
        if (std.mem.eql(u8, std.mem.sliceTo(&m.name, 0), name)) return @intCast(i);
    }
    return -1;
}

fn getMapMut(s: *State, id: i32) ?*Map {
    if (id < 0 or @as(u32, @intCast(id)) >= s.map_count) return null;
    return &s.maps.?[@intCast(id)];
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

/// Marks in `claimed` every key and mouse button the binding reads.
fn claim(b: *const Binding, keys: []u64, buttons: *u32) void {
    const codes = [_]c_int{ b.k0, b.k1, b.k2, b.k3 };
    const used: usize = switch (b.kind) {
        .key, .mouse_button => 1,
        .key_pair => 2,
        .key_quad => 4,
    };
    for (codes[0..used]) |code| {
        if (code < 0) continue;
        if (b.kind == .mouse_button) {
            if (code < 32) buttons.* |= @as(u32, 1) << @intCast(code);
        } else if (code < key_bit_count) {
            const k: usize = @intCast(code);
            keys[k / 64] |= @as(u64, 1) << @intCast(k % 64);
        }
    }
}

/// Slot `add_map`. Returns -1 for a null handle, a null, empty or duplicated name, and when the
/// array cannot grow; none of them changes the maps.
fn vtAddMap(self_in: ?*abi_input_actions.c.ke_input_actions, name: [*c]const u8, priority: i32) callconv(.c) i32 {
    const self = self_in orelse return -1;
    if (name == null or name[0] == 0) return -1;
    const s = stateOf(self);
    const n = std.mem.span(name);
    if (findMapByName(s, n) >= 0) return -1;
    if (!ensureMapCapacity(s, s.map_count + 1)) return -1;
    const m = &s.maps.?[s.map_count];
    m.* = .{ .name = [_]u8{0} ** action_name_max, .priority = priority, .enabled = true };
    copyName(&m.name, n);
    s.map_count += 1;
    return @intCast(s.map_count - 1);
}

/// Slot `get_map_id`. -1 for a null handle or name and for a name no map has.
fn vtGetMapId(self_in: ?*abi_input_actions.c.ke_input_actions, name: [*c]const u8) callconv(.c) i32 {
    const self = self_in orelse return -1;
    if (name == null) return -1;
    return findMapByName(stateOf(self), std.mem.span(name));
}

/// Slot `set_map_enabled`. Invalid argument for a null handle, not found for an unknown id.
fn vtSetMapEnabled(self_in: ?*abi_input_actions.c.ke_input_actions, id: i32, enabled: bool) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    const m = getMapMut(stateOf(self), id) orelse return R.code(error.NotFound);
    m.enabled = enabled;
    return R.ok;
}

/// Slot `is_map_enabled`. False for a null handle and an unknown id.
fn vtIsMapEnabled(self_in: ?*abi_input_actions.c.ke_input_actions, id: i32) callconv(.c) bool {
    const self = self_in orelse return false;
    const m = getMapMut(stateOf(self), id) orelse return false;
    return m.enabled;
}

/// Slot `get_action_id`. -1 for a null handle or name and for a name no action has.
fn vtGetActionId(self_in: ?*abi_input_actions.c.ke_input_actions, name: [*c]const u8) callconv(.c) i32 {
    const self = self_in orelse return -1;
    if (name == null) return -1;
    return findActionByName(stateOf(self), std.mem.span(name));
}

/// Slot `add_action`. Appends the action after those already present, so earlier ids keep their
/// meaning. Returns -1 for a null handle, an unknown map, a null, empty or duplicated name, and
/// when the array cannot grow; none of them changes the actions.
fn vtAddAction(
    self_in: ?*abi_input_actions.c.ke_input_actions,
    map_id: i32,
    name: [*c]const u8,
    action_type: abi_input_actions.c.ke_action_type,
) callconv(.c) i32 {
    const self = self_in orelse return -1;
    if (name == null or name[0] == 0) return -1;
    const s = stateOf(self);
    if (getMapMut(s, map_id) == null) return -1;
    const n = std.mem.span(name);
    if (findActionByName(s, n) >= 0) return -1;
    if (!ensureActionCapacity(s, s.action_count + 1)) return -1;

    const act = &s.actions.?[s.action_count];
    act.* = Action.blank();
    copyName(&act.name, n);
    act.map = @intCast(map_id);
    act.type = action_type;
    s.action_count += 1;
    return @intCast(s.action_count - 1);
}

fn getActionMut(s: *State, id: i32) ?*Action {
    if (id < 0 or @as(u32, @intCast(id)) >= s.action_count) return null;
    return &s.actions.?[@intCast(id)];
}

fn appendBinding(s: *State, id: i32, b: Binding) abi_result.c.ke_result {
    const a = getActionMut(s, id) orelse return R.code(error.NotFound);
    if (!ensureBindingCapacity(a, a.binding_count + 1)) return R.code(error.OutOfMemory);
    a.bindings.?[a.binding_count] = b;
    a.binding_count += 1;
    return R.ok;
}

/// Slot `bind_key`. Stores the key code as given; a code the snapshot cannot carry is never
/// reported held. A null handle is an invalid argument, an id that names no action is not found,
/// and a binding array that cannot grow is out of memory.
fn vtBindKey(self_in: ?*abi_input_actions.c.ke_input_actions, action_id: i32, key: abi_input.c.ke_key) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    return appendBinding(stateOf(self), action_id, .{ .kind = .key, .k0 = @intCast(key) });
}

/// Slot `bind_mouse_button`. Failures are those of `vtBindKey`.
fn vtBindMouseButton(self_in: ?*abi_input_actions.c.ke_input_actions, action_id: i32, button: abi_input.c.ke_mouse_button) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    return appendBinding(stateOf(self), action_id, .{ .kind = .mouse_button, .k0 = @intCast(button) });
}

/// Slot `bind_key_pair`. Failures are those of `vtBindKey`.
fn vtBindKeyPair(self_in: ?*abi_input_actions.c.ke_input_actions, action_id: i32, neg: abi_input.c.ke_key, pos: abi_input.c.ke_key) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    return appendBinding(stateOf(self), action_id, .{ .kind = .key_pair, .k0 = @intCast(neg), .k1 = @intCast(pos) });
}

/// Slot `bind_key_quad`. Failures are those of `vtBindKey`.
fn vtBindKeyQuad(
    self_in: ?*abi_input_actions.c.ke_input_actions,
    action_id: i32,
    up: abi_input.c.ke_key,
    down: abi_input.c.ke_key,
    left: abi_input.c.ke_key,
    right: abi_input.c.ke_key,
) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    return appendBinding(stateOf(self), action_id, .{ .kind = .key_quad, .k0 = @intCast(up), .k1 = @intCast(down), .k2 = @intCast(left), .k3 = @intCast(right) });
}

/// Slot `evaluate`. A button action is active when any binding is, and an axis action takes the
/// largest magnitude per component. A null handle or snapshot is an invalid argument and changes
/// nothing; an order that cannot be allocated is out of memory, also changing nothing.
fn vtEvaluate(self_in: ?*abi_input_actions.c.ke_input_actions, snapshot_in: ?*const abi_input.c.ke_input_snapshot) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    const snapshot = snapshot_in orelse return R.code(error.InvalidArgument);
    const s = stateOf(self);
    if (s.action_count == 0) return R.ok;

    const order = heap.gpa.alloc(u32, s.map_count) catch return R.code(error.OutOfMemory);
    defer heap.gpa.free(order);
    for (order, 0..) |*o, i| o.* = @intCast(i);
    const maps = s.maps.?[0..s.map_count];
    std.sort.insertion(u32, order, maps, struct {
        fn higher(ms: []Map, a: u32, b: u32) bool {
            return ms[a].priority > ms[b].priority;
        }
    }.higher);

    var masked = snapshot.*;
    for (s.actions.?[0..s.action_count]) |*a| a.prev_active = a.curr_active;

    for (order) |map_index| {
        const map = &maps[map_index];
        var claimed_keys = std.mem.zeroes(@TypeOf(masked.keys_down));
        var claimed_buttons: u32 = 0;
        for (s.actions.?[0..s.action_count]) |*a| {
            if (a.map != map_index) continue;
            var acc: Sample = .{};
            var any_active = false;
            if (a.bindings) |bindings| for (bindings[0..a.binding_count]) |*b| {
                if (!map.enabled) continue;
                claim(b, &claimed_keys, &claimed_buttons);
                const sampled, const active = sampleBinding(b, &masked);
                if (!active) continue;
                any_active = true;
                if (a.type == abi_input_actions.c.KE_ACTION_TYPE_BUTTON) {
                    acc.x = 1.0;
                } else {
                    if (@abs(sampled.x) > @abs(acc.x)) acc.x = sampled.x;
                    if (@abs(sampled.y) > @abs(acc.y)) acc.y = sampled.y;
                    if (@abs(sampled.z) > @abs(acc.z)) acc.z = sampled.z;
                }
            };
            a.curr_x = acc.x;
            a.curr_y = acc.y;
            a.curr_z = acc.z;
            a.curr_active = any_active;
        }
        for (&masked.keys_down, claimed_keys) |*word, claimed| word.* &= ~claimed;
        masked.mouse_buttons_down &= ~claimed_buttons;
    }
    return R.ok;
}

fn getAction(self_in: ?*abi_input_actions.c.ke_input_actions, id: i32) ?*const Action {
    const self = self_in orelse return null;
    return getActionMut(stateOf(self), id);
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
    return a.curr_active and !a.prev_active;
}

/// Slot `was_action_released`. True when the last evaluation made the action inactive; false for
/// an unknown id.
fn vtWasActionReleased(self_in: ?*abi_input_actions.c.ke_input_actions, id: i32) callconv(.c) bool {
    const a = getAction(self_in, id) orelse return false;
    return !a.curr_active and a.prev_active;
}

/// Slot `get_axis1d`. The stored x value; zero for an unknown id.
fn vtGetAxis1d(self_in: ?*abi_input_actions.c.ke_input_actions, id: i32) callconv(.c) f32 {
    const a = getAction(self_in, id) orelse return 0.0;
    return a.curr_x;
}

/// Slot `get_axis2d`. Writes the stored x and y to the non-null outputs; zero for an unknown id.
fn vtGetAxis2d(self_in: ?*abi_input_actions.c.ke_input_actions, id: i32, out_x: [*c]f32, out_y: [*c]f32) callconv(.c) void {
    const a = getAction(self_in, id);
    if (out_x != null) out_x.* = if (a) |act| act.curr_x else 0.0;
    if (out_y != null) out_y.* = if (a) |act| act.curr_y else 0.0;
}

/// Slot `get_axis3d`. Writes the stored x, y and z to the non-null outputs; zero for an unknown id.
fn vtGetAxis3d(self_in: ?*abi_input_actions.c.ke_input_actions, id: i32, out_x: [*c]f32, out_y: [*c]f32, out_z: [*c]f32) callconv(.c) void {
    const a = getAction(self_in, id);
    if (out_x != null) out_x.* = if (a) |act| act.curr_x else 0.0;
    if (out_y != null) out_y.* = if (a) |act| act.curr_y else 0.0;
    if (out_z != null) out_z.* = if (a) |act| act.curr_z else 0.0;
}

/// The destroy of the handle. Frees the bindings, the arrays and the `State`.
fn vtDestroy(self_in: ?*abi_input_actions.c.ke_input_actions) callconv(.c) void {
    const self = self_in orelse return;
    const s = stateOf(self);
    if (s.runtime) |rt| _ = rt.unregister_system.?(rt, s.system);
    if (s.actions) |actions| {
        for (actions[0..s.action_count]) |*a| {
            if (a.bindings) |b| heap.gpa.free(b[0..a.binding_capacity]);
        }
        heap.gpa.free(actions[0..s.action_capacity]);
    }
    if (s.maps) |maps| heap.gpa.free(maps[0..s.map_capacity]);
    heap.gpa.destroy(s);
}

/// What a walk of the configuration reads from and where it adds, and the first failure it met.
const Reader = struct {
    api: *abi_input_actions.c.ke_input_actions,
    cfg: *abi_configuration.c.ke_configuration,
    failure: ?R.Error = null,

    fn fail(r: *Reader, err: R.Error, comptime fmt: []const u8, args: anytype) void {
        log.warn(fmt, args);
        if (r.failure == null) r.failure = err;
    }

    fn string(r: *Reader, section: [:0]const u8, key: [*:0]const u8) ?[*:0]const u8 {
        const v = r.cfg.get_string.?(r.cfg, section.ptr, key, null);
        return if (v == null) null else @ptrCast(v);
    }
};

/// What one level of the walk lists the children of.
const Walk = struct {
    reader: *Reader,
    parent: [:0]const u8,
    map: i32 = -1,
    action: i32 = -1,
};

fn listChildren(w: *Walk, comptime each: fn (*Walk, [:0]const u8) void) void {
    if (w.reader.failure != null) return;
    const Thunk = struct {
        fn call(name: [*c]const u8, ctx: ?*anyopaque) callconv(.c) void {
            const walk: *Walk = @ptrCast(@alignCast(ctx.?));
            if (walk.reader.failure != null) return;
            each(walk, std.mem.span(@as([*:0]const u8, @ptrCast(name))));
        }
    };
    R.check(w.reader.cfg.for_each_child.?(w.reader.cfg, w.parent.ptr, Thunk.call, w)) catch |err|
        w.reader.fail(err, "listing {s} failed: {t}", .{ w.parent, err });
}

fn childSection(w: *Walk, a: []const u8, b: []const u8) ?[:0]u8 {
    return std.fmt.allocPrintSentinel(heap.gpa, "{s}.{s}{s}", .{ w.parent, a, b }, 0) catch {
        w.reader.fail(error.OutOfMemory, "reading the input maps ran out of memory", .{});
        return null;
    };
}

fn readMap(w: *Walk, name: [:0]const u8) void {
    const r = w.reader;
    const section = childSection(w, name, "") orelse return;
    defer heap.gpa.free(section);
    const priority = r.cfg.get_int.?(r.cfg, section.ptr, "priority", 0);
    const map = r.api.add_map.?(r.api, name.ptr, @intCast(std.math.clamp(priority, std.math.minInt(i32), std.math.maxInt(i32))));
    if (map < 0) return r.fail(error.InvalidArgument, "input map '{s}' could not be added", .{name});
    if (!r.cfg.get_bool.?(r.cfg, section.ptr, "enabled", true)) _ = r.api.set_map_enabled.?(r.api, map, false);
    const actions = std.fmt.allocPrintSentinel(heap.gpa, "{s}.action", .{section}, 0) catch
        return r.fail(error.OutOfMemory, "reading the input maps ran out of memory", .{});
    defer heap.gpa.free(actions);
    var inner: Walk = .{ .reader = r, .parent = actions, .map = map };
    listChildren(&inner, readAction);
}

fn readAction(w: *Walk, name: [:0]const u8) void {
    const r = w.reader;
    const section = childSection(w, name, "") orelse return;
    defer heap.gpa.free(section);
    var action_type: abi_input_actions.c.ke_action_type = abi_input_actions.c.KE_ACTION_TYPE_BUTTON;
    if (r.string(section, "type")) |t| action_type = parseActionType(t) orelse
        return r.fail(error.InvalidArgument, "action '{s}': '{s}' is not an action type", .{ name, t });
    const action = r.api.add_action.?(r.api, w.map, name.ptr, action_type);
    if (action < 0) return r.fail(error.InvalidArgument, "action '{s}' could not be added", .{name});
    const bindings = std.fmt.allocPrintSentinel(heap.gpa, "{s}.bindings", .{section}, 0) catch
        return r.fail(error.OutOfMemory, "reading the input maps ran out of memory", .{});
    defer heap.gpa.free(bindings);
    var inner: Walk = .{ .reader = r, .parent = bindings, .map = w.map, .action = action };
    listChildren(&inner, readBinding);
}

fn keyOf(r: *Reader, section: [:0]const u8, key: [*:0]const u8) ?abi_input.c.ke_key {
    const name = r.string(section, key) orelse {
        r.fail(error.InvalidArgument, "binding {s} has no {s}", .{ section, key });
        return null;
    };
    const code = lookupKey(name);
    if (code < 0) {
        r.fail(error.InvalidArgument, "binding {s}: '{s}' is not a key name", .{ section, name });
        return null;
    }
    return @intCast(code);
}

fn readBinding(w: *Walk, index: [:0]const u8) void {
    const r = w.reader;
    const section = childSection(w, index, "") orelse return;
    defer heap.gpa.free(section);
    const kind = std.mem.span(r.string(section, "kind") orelse
        return r.fail(error.InvalidArgument, "binding {s} has no kind", .{section}));
    const a = w.action;
    const result = if (std.mem.eql(u8, kind, "key"))
        r.api.bind_key.?(r.api, a, keyOf(r, section, "key") orelse return)
    else if (std.mem.eql(u8, kind, "key_pair"))
        r.api.bind_key_pair.?(r.api, a, keyOf(r, section, "negative") orelse return, keyOf(r, section, "positive") orelse return)
    else if (std.mem.eql(u8, kind, "key_quad"))
        r.api.bind_key_quad.?(r.api, a, keyOf(r, section, "up") orelse return, keyOf(r, section, "down") orelse return, keyOf(r, section, "left") orelse return, keyOf(r, section, "right") orelse return)
    else if (std.mem.eql(u8, kind, "mouse")) blk: {
        const name = r.string(section, "button") orelse return r.fail(error.InvalidArgument, "binding {s} has no button", .{section});
        const code = lookupMouseButton(name);
        if (code < 0) return r.fail(error.InvalidArgument, "binding {s}: '{s}' is not a mouse button name", .{ section, name });
        break :blk r.api.bind_mouse_button.?(r.api, a, @intCast(code));
    } else return r.fail(error.InvalidArgument, "binding {s}: '{s}' is not a binding kind", .{ section, kind });
    R.check(result) catch |err| r.fail(err, "binding {s} could not be added: {t}", .{ section, err });
}

/// Factory. Builds an empty set of maps, then adds those the configuration describes through the
/// vtable's own slots; any failure frees what was built and leaves the handle zeroed.
/// The PreUpdate system the factory registers when it is given a runtime: it advances the input's
/// frame and evaluates the maps against its snapshot, before any behaviour reads an action.
fn pump(_: ?*abi_runtime.c.ke_system_ctx, user_data: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const s: *State = @ptrCast(@alignCast(user_data orelse return R.code(error.InvalidArgument)));
    const input = s.input orelse return R.code(error.InvalidArgument);
    input.update.?(input);
    var snapshot: abi_input.c.ke_input_snapshot = undefined;
    input.get_snapshot.?(input, &snapshot);
    return vtEvaluate(&s.api, &snapshot);
}

export fn ke_input_actions_create(
    runtime: ?*abi_runtime.c.ke_runtime,
    input: ?*abi_input.c.ke_input,
    configuration: ?*abi_configuration.c.ke_configuration,
    config: ?*const abi_framework_factory.c.ke_input_actions_config,
    out_actions: ?*abi_input_actions.c.ke_input_actions_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_actions orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_input_actions.c.ke_input_actions_handle);
    if (runtime != null and input == null) {
        log.warn("input actions: a runtime is given without the input to read", .{});
        return R.code(error.InvalidArgument);
    }

    const s = heap.gpa.create(State) catch |err| return R.code(err);
    s.* = .{ .api = std.mem.zeroes(abi_input_actions.c.ke_input_actions) };
    s.api.handle = s;
    s.api.add_map = vtAddMap;
    s.api.get_map_id = vtGetMapId;
    s.api.set_map_enabled = vtSetMapEnabled;
    s.api.is_map_enabled = vtIsMapEnabled;
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

    if (configuration) |cfg| {
        const given = config orelse {
            log.warn("input actions: a configuration is given without the config naming its section", .{});
            vtDestroy(&s.api);
            return R.code(error.InvalidArgument);
        };
        const section_name: [*:0]const u8 = @ptrCast(given.section orelse {
            log.warn("input actions: the config names no section", .{});
            vtDestroy(&s.api);
            return R.code(error.InvalidArgument);
        });
        const maps = std.fmt.allocPrintSentinel(heap.gpa, "{s}.map", .{std.mem.span(section_name)}, 0) catch {
            vtDestroy(&s.api);
            return R.code(error.OutOfMemory);
        };
        defer heap.gpa.free(maps);
        var reader: Reader = .{ .api = &s.api, .cfg = cfg };
        var walk: Walk = .{ .reader = &reader, .parent = maps };
        listChildren(&walk, readMap);
        if (reader.failure) |err| {
            vtDestroy(&s.api);
            return R.code(err);
        }
    }

    if (runtime) |rt| {
        var params = std.mem.zeroes(abi_runtime.c.ke_runtime_system_params);
        params.name = "input.actions";
        params.phase = abi_runtime.c.KE_PHASE_PRE_UPDATE;
        params.exclusive = true;
        params.user_data = s;
        params.execute = pump;
        const registered = rt.register_system.?(rt, &params, &s.system);
        if (registered != R.ok) {
            vtDestroy(&s.api);
            return registered;
        }
        s.runtime = rt;
        s.input = input;
    }

    out.* = .{ .ref = &s.api, .destroy = vtDestroy };
    return R.ok;
}

const testing = std.testing;

const FakeConfig = struct {
    const Value = union(enum) { str: [*:0]const u8, int: i64, boolean: bool };
    const Entry = struct { section: []const u8, key: []const u8, value: Value };

    var entries: []const Entry = &.{};

    fn api(with: []const Entry) abi_configuration.c.ke_configuration {
        entries = with;
        var cfg = std.mem.zeroes(abi_configuration.c.ke_configuration);
        cfg.get_string = getString;
        cfg.get_int = getInt;
        cfg.get_bool = getBool;
        cfg.for_each_child = forEachChild;
        return cfg;
    }

    fn find(section: [*c]const u8, key: [*c]const u8) ?Value {
        for (entries) |e| {
            if (std.mem.eql(u8, e.section, std.mem.span(section)) and std.mem.eql(u8, e.key, std.mem.span(key))) return e.value;
        }
        return null;
    }

    fn getString(_: [*c]abi_configuration.c.ke_configuration, section: [*c]const u8, key: [*c]const u8, fallback: [*c]const u8) callconv(.c) [*c]const u8 {
        return if (find(section, key)) |v| switch (v) {
            .str => |s| s,
            else => fallback,
        } else fallback;
    }

    fn getInt(_: [*c]abi_configuration.c.ke_configuration, section: [*c]const u8, key: [*c]const u8, fallback: i64) callconv(.c) i64 {
        return if (find(section, key)) |v| switch (v) {
            .int => |i| i,
            else => fallback,
        } else fallback;
    }

    fn getBool(_: [*c]abi_configuration.c.ke_configuration, section: [*c]const u8, key: [*c]const u8, fallback: bool) callconv(.c) bool {
        return if (find(section, key)) |v| switch (v) {
            .boolean => |b| b,
            else => fallback,
        } else fallback;
    }

    fn forEachChild(_: [*c]abi_configuration.c.ke_configuration, section: [*c]const u8, each: abi_configuration.c.ke_configuration_child_func, ctx: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
        const parent = std.mem.span(section);
        var seen: [16][]const u8 = undefined;
        var count: usize = 0;
        outer: for (entries) |e| {
            if (e.section.len <= parent.len + 1 or !std.mem.startsWith(u8, e.section, parent) or e.section[parent.len] != '.') continue;
            const rest = e.section[parent.len + 1 ..];
            const child = rest[0 .. std.mem.indexOfScalar(u8, rest, '.') orelse rest.len];
            for (seen[0..count]) |n| if (std.mem.eql(u8, n, child)) continue :outer;
            seen[count] = child;
            count += 1;
            var buf: [64]u8 = undefined;
            @memcpy(buf[0..child.len], child);
            buf[child.len] = 0;
            each.?(@ptrCast(&buf), ctx);
        }
        return R.ok;
    }
};

const Actions = struct {
    handle: abi_input_actions.c.ke_input_actions_handle,

    fn init() !Actions {
        var h = std.mem.zeroes(abi_input_actions.c.ke_input_actions_handle);
        try testing.expectEqual(R.ok, ke_input_actions_create(null, null, null, null, &h));
        return .{ .handle = h };
    }

    fn from(entries: []const FakeConfig.Entry) !Actions {
        var cfg = FakeConfig.api(entries);
        var h = std.mem.zeroes(abi_input_actions.c.ke_input_actions_handle);
        try R.check(ke_input_actions_create(null, null, &cfg, &.{ .section = "input" }, &h));
        return .{ .handle = h };
    }

    fn api(self: *const Actions) *abi_input_actions.c.ke_input_actions {
        return @ptrCast(self.handle.ref);
    }

    fn action(self: *const Actions, map: i32, name: [*:0]const u8, t: abi_input_actions.c.ke_action_type) i32 {
        return self.api().add_action.?(self.api(), map, name, t);
    }

    fn eval(self: *const Actions, snapshot: *const abi_input.c.ke_input_snapshot) !void {
        try testing.expectEqual(R.ok, self.api().evaluate.?(self.api(), snapshot));
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

fn held(keys: []const c_int) abi_input.c.ke_input_snapshot {
    var snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);
    for (keys) |k| pressKey(&snapshot, k);
    return snapshot;
}

test "creating without a configuration yields no map and no action" {
    var a = try Actions.init();
    defer a.deinit();
    try testing.expectEqual(@as(i32, -1), a.api().get_map_id.?(a.api(), "Game"));
    try testing.expectEqual(@as(i32, -1), a.api().get_action_id.?(a.api(), "Jump"));
}

test "a key bound by hand drives its button, pressed only on the first evaluation it is held" {
    var a = try Actions.init();
    defer a.deinit();
    const map = a.api().add_map.?(a.api(), "Game", 0);
    const id = a.action(map, "Jump", abi_input_actions.c.KE_ACTION_TYPE_BUTTON);
    try testing.expectEqual(R.ok, a.api().bind_key.?(a.api(), id, abi_input.c.KE_KEY_SPACE));

    const snapshot = held(&.{abi_input.c.KE_KEY_SPACE});
    try a.eval(&snapshot);
    try testing.expect(a.api().is_action_down.?(a.api(), id));
    try testing.expect(a.api().was_action_pressed.?(a.api(), id));
    try a.eval(&snapshot);
    try testing.expect(!a.api().was_action_pressed.?(a.api(), id));
    try a.eval(&std.mem.zeroes(abi_input.c.ke_input_snapshot));
    try testing.expect(a.api().was_action_released.?(a.api(), id));
}

test "a key pair reads one at each end, and a key quad drives two axes" {
    var a = try Actions.init();
    defer a.deinit();
    const map = a.api().add_map.?(a.api(), "Game", 0);
    const strafe = a.action(map, "Strafe", abi_input_actions.c.KE_ACTION_TYPE_AXIS1D);
    const move = a.action(map, "Move", abi_input_actions.c.KE_ACTION_TYPE_AXIS2D);
    try testing.expectEqual(R.ok, a.api().bind_key_pair.?(a.api(), strafe, abi_input.c.KE_KEY_A, abi_input.c.KE_KEY_D));
    try testing.expectEqual(R.ok, a.api().bind_key_quad.?(a.api(), move, abi_input.c.KE_KEY_UP, abi_input.c.KE_KEY_DOWN, abi_input.c.KE_KEY_LEFT, abi_input.c.KE_KEY_RIGHT));

    try a.eval(&held(&.{ abi_input.c.KE_KEY_A, abi_input.c.KE_KEY_UP, abi_input.c.KE_KEY_RIGHT }));
    try testing.expectEqual(@as(f32, -1.0), a.api().get_axis1d.?(a.api(), strafe));
    var x: f32 = 0;
    var y: f32 = 0;
    a.api().get_axis2d.?(a.api(), move, &x, &y);
    try testing.expectEqual(@as(f32, 1.0), x);
    try testing.expectEqual(@as(f32, 1.0), y);
}

test "a mouse button bound by hand drives its action" {
    var a = try Actions.init();
    defer a.deinit();
    const id = a.action(a.api().add_map.?(a.api(), "Game", 0), "Fire", abi_input_actions.c.KE_ACTION_TYPE_BUTTON);
    try testing.expectEqual(R.ok, a.api().bind_mouse_button.?(a.api(), id, abi_input.c.KE_MOUSE_BUTTON_LEFT));
    var snapshot = std.mem.zeroes(abi_input.c.ke_input_snapshot);
    snapshot.mouse_buttons_down = @as(u32, 1) << @intCast(abi_input.c.KE_MOUSE_BUTTON_LEFT);
    try a.eval(&snapshot);
    try testing.expect(a.api().is_action_down.?(a.api(), id));
}

test "a duplicated, empty or absent name, or an unknown map, is refused" {
    var a = try Actions.init();
    defer a.deinit();
    const map = a.api().add_map.?(a.api(), "Game", 0);
    try testing.expectEqual(@as(i32, -1), a.api().add_map.?(a.api(), "Game", 1));
    try testing.expectEqual(@as(i32, -1), a.api().add_map.?(a.api(), "", 1));
    try testing.expect(a.action(map, "Jump", abi_input_actions.c.KE_ACTION_TYPE_BUTTON) >= 0);
    try testing.expectEqual(@as(i32, -1), a.action(map, "Jump", abi_input_actions.c.KE_ACTION_TYPE_BUTTON));
    try testing.expectEqual(@as(i32, -1), a.action(map, "", abi_input_actions.c.KE_ACTION_TYPE_BUTTON));
    try testing.expectEqual(@as(i32, -1), a.action(7, "Run", abi_input_actions.c.KE_ACTION_TYPE_BUTTON));
    try testing.expectEqual(R.code(error.NotFound), a.api().bind_key.?(a.api(), 99, abi_input.c.KE_KEY_SPACE));
    try testing.expectEqual(R.code(error.NotFound), a.api().set_map_enabled.?(a.api(), 9, false));
    try testing.expectEqual(R.code(error.InvalidArgument), a.api().evaluate.?(a.api(), null));
}

test "a key bound in a higher priority map is not seen by a lower one" {
    var a = try Actions.init();
    defer a.deinit();
    const game = a.api().add_map.?(a.api(), "Game", 0);
    const menu = a.api().add_map.?(a.api(), "Menu", 10);
    const jump = a.action(game, "Jump", abi_input_actions.c.KE_ACTION_TYPE_BUTTON);
    const accept = a.action(menu, "Accept", abi_input_actions.c.KE_ACTION_TYPE_BUTTON);
    try testing.expectEqual(R.ok, a.api().bind_key.?(a.api(), jump, abi_input.c.KE_KEY_SPACE));
    try testing.expectEqual(R.ok, a.api().bind_key.?(a.api(), accept, abi_input.c.KE_KEY_SPACE));

    const space = held(&.{abi_input.c.KE_KEY_SPACE});
    try a.eval(&space);
    try testing.expect(a.api().is_action_down.?(a.api(), accept));
    try testing.expect(!a.api().is_action_down.?(a.api(), jump));
}

test "a disabled map holds no active action and hides no key from the maps below it" {
    var a = try Actions.init();
    defer a.deinit();
    const game = a.api().add_map.?(a.api(), "Game", 0);
    const menu = a.api().add_map.?(a.api(), "Menu", 10);
    const jump = a.action(game, "Jump", abi_input_actions.c.KE_ACTION_TYPE_BUTTON);
    const accept = a.action(menu, "Accept", abi_input_actions.c.KE_ACTION_TYPE_BUTTON);
    try testing.expectEqual(R.ok, a.api().bind_key.?(a.api(), jump, abi_input.c.KE_KEY_SPACE));
    try testing.expectEqual(R.ok, a.api().bind_key.?(a.api(), accept, abi_input.c.KE_KEY_SPACE));

    const space = held(&.{abi_input.c.KE_KEY_SPACE});
    try a.eval(&space);
    try testing.expectEqual(R.ok, a.api().set_map_enabled.?(a.api(), menu, false));
    try testing.expect(!a.api().is_map_enabled.?(a.api(), menu));
    try a.eval(&space);
    try testing.expect(!a.api().is_action_down.?(a.api(), accept));
    try testing.expect(a.api().was_action_released.?(a.api(), accept));
    try testing.expect(a.api().is_action_down.?(a.api(), jump));
}

test "the maps, actions and bindings a configuration describes are added through the slots" {
    var a = try Actions.from(&.{
        .{ .section = "input.map.Game", .key = "priority", .value = .{ .int = 0 } },
        .{ .section = "input.map.Game.action.Move", .key = "type", .value = .{ .str = "Axis1D" } },
        .{ .section = "input.map.Game.action.Move.bindings.0", .key = "kind", .value = .{ .str = "key_pair" } },
        .{ .section = "input.map.Game.action.Move.bindings.0", .key = "negative", .value = .{ .str = "S" } },
        .{ .section = "input.map.Game.action.Move.bindings.0", .key = "positive", .value = .{ .str = "W" } },
        .{ .section = "input.map.Game.action.Fire.bindings.0", .key = "kind", .value = .{ .str = "mouse" } },
        .{ .section = "input.map.Game.action.Fire.bindings.0", .key = "button", .value = .{ .str = "Left" } },
        .{ .section = "input.map.Menu", .key = "priority", .value = .{ .int = 10 } },
        .{ .section = "input.map.Menu", .key = "enabled", .value = .{ .boolean = false } },
        .{ .section = "input.map.Menu.action.Accept.bindings.0", .key = "kind", .value = .{ .str = "key" } },
        .{ .section = "input.map.Menu.action.Accept.bindings.0", .key = "key", .value = .{ .str = "W" } },
    });
    defer a.deinit();
    const menu = a.api().get_map_id.?(a.api(), "Menu");
    try testing.expect(menu >= 0);
    try testing.expect(!a.api().is_map_enabled.?(a.api(), menu));
    const move = a.api().get_action_id.?(a.api(), "Move");
    try a.eval(&held(&.{abi_input.c.KE_KEY_W}));
    try testing.expectEqual(@as(f32, 1.0), a.api().get_axis1d.?(a.api(), move));
    try testing.expect(a.api().get_action_id.?(a.api(), "Fire") >= 0);
}

test "a misspelt key, an unknown kind or type, or a binding missing a key fails the create" {
    const cases = [_][]const FakeConfig.Entry{
        &.{ .{ .section = "input.map.G.action.J.bindings.0", .key = "kind", .value = .{ .str = "key" } }, .{ .section = "input.map.G.action.J.bindings.0", .key = "key", .value = .{ .str = "Spcae" } } },
        &.{.{ .section = "input.map.G.action.J.bindings.0", .key = "kind", .value = .{ .str = "chord" } }},
        &.{.{ .section = "input.map.G.action.J", .key = "type", .value = .{ .str = "Axis4D" } }},
        &.{.{ .section = "input.map.G.action.J.bindings.0", .key = "kind", .value = .{ .str = "key_pair" } }},
    };
    for (cases) |entries| {
        var cfg = FakeConfig.api(entries);
        var h = std.mem.zeroes(abi_input_actions.c.ke_input_actions_handle);
        try testing.expectError(error.InvalidArgument, R.check(ke_input_actions_create(null, null, &cfg, &.{ .section = "input" }, &h)));
        try testing.expect(h.ref == null);
    }
}

var pumped: abi_runtime.c.ke_runtime_system_params = undefined;

fn keepSystem(args: zsub.For(abi_runtime.c.ke_runtime).Args(.register_system)) abi_result.c.ke_result {
    pumped = args[1].?.*;
    args[2].?.* = 7;
    return R.ok;
}

test "given a runtime, the maps register a PreUpdate system that advances the input and evaluates them, and unregister it when destroyed" {
    var rt: zsub.For(abi_runtime.c.ke_runtime) = undefined;
    try rt.init();
    defer rt.deinit();
    var input: zsub.For(abi_input.c.ke_input) = undefined;
    try input.init();
    defer input.deinit();
    _ = rt.when(.register_system).does(keepSystem);
    var h: abi_input_actions.c.ke_input_actions_handle = undefined;
    try R.check(ke_input_actions_create(rt.api(), input.api(), null, null, &h));
    try testing.expectEqual(abi_runtime.c.KE_PHASE_PRE_UPDATE, pumped.phase);
    try R.check(pumped.execute.?(null, pumped.user_data, 0));
    try input.received(.update).times(1);
    try input.received(.get_snapshot).times(1);
    h.destroy.?(h.ref);
    try rt.received(.unregister_system).where(zsub.argIs(1, @as(abi_runtime.c.ke_system_id, 7))).times(1);
}

test "a runtime without the input to read is refused" {
    var rt: zsub.For(abi_runtime.c.ke_runtime) = undefined;
    try rt.init();
    defer rt.deinit();
    var h: abi_input_actions.c.ke_input_actions_handle = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), ke_input_actions_create(rt.api(), null, null, null, &h));
}

test "creating and destroying the action maps leaves no block allocated" {
    var actions = try Actions.init();
    actions.deinit();
    try heap.expectNoLeaks();
}
