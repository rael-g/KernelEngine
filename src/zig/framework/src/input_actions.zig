// ke_input_actions impl. Parses `.input` TOML files into an internal table of
// actions + bindings, evaluates them against ke_input_snapshot per frame, and
// exposes polling + event paths. Schema:
//
//     [action.NAME]
//     type = "Button" | "Axis1D" | "Axis2D" | "Axis3D"
//     bindings = [
//         { kind = "key",        key      = "Space" },
//         { kind = "key_pair",   negative = "S",      positive = "W" },
//         { kind = "key_quad",   up = "W", down = "S", left = "A", right = "D" },
//         { kind = "mouse",      button   = "Left" },
//     ]
//
// Action ids are assigned in declaration order (first action = 0). Callers
// cache them via get_action_id() after load and reuse across frames.

const std = @import("std");

const c = @import("c.zig").c;
const heap = @import("heap.zig");

const E = @import("kerror").Errors(c);

/// Action names are stored inline; longer names are truncated at load.
const action_name_max = 64;

const action_initial_capacity: u32 = 8;
const binding_initial_capacity: u32 = 4;

/// How many keys the snapshot's bitset can represent, taken from the bitset
/// itself so the two can never disagree.
const key_bit_count: c_int = @intCast(
    @typeInfo(@FieldType(c.ke_input_snapshot, "keys_down")).array.len * 64,
);

// -- name -> enum lookup tables ----------------------------------------------
//
// Linear-scan arrays consulted only at .input parse time, never in the
// per-frame evaluate path, so a hash would buy nothing. Order is irrelevant.

const KeyNameEntry = struct { name: []const u8, code: c_int };

const key_table = [_]KeyNameEntry{
    .{ .name = "Unknown", .code = c.KE_KEY_UNKNOWN },   .{ .name = "Space", .code = c.KE_KEY_SPACE },
    .{ .name = "Apostrophe", .code = c.KE_KEY_APOSTROPHE }, .{ .name = "Comma", .code = c.KE_KEY_COMMA },
    .{ .name = "Minus", .code = c.KE_KEY_MINUS },       .{ .name = "Period", .code = c.KE_KEY_PERIOD },
    .{ .name = "Slash", .code = c.KE_KEY_SLASH },
    .{ .name = "Number0", .code = c.KE_KEY_NUMBER_0 },  .{ .name = "Number1", .code = c.KE_KEY_NUMBER_1 },
    .{ .name = "Number2", .code = c.KE_KEY_NUMBER_2 },  .{ .name = "Number3", .code = c.KE_KEY_NUMBER_3 },
    .{ .name = "Number4", .code = c.KE_KEY_NUMBER_4 },  .{ .name = "Number5", .code = c.KE_KEY_NUMBER_5 },
    .{ .name = "Number6", .code = c.KE_KEY_NUMBER_6 },  .{ .name = "Number7", .code = c.KE_KEY_NUMBER_7 },
    .{ .name = "Number8", .code = c.KE_KEY_NUMBER_8 },  .{ .name = "Number9", .code = c.KE_KEY_NUMBER_9 },
    .{ .name = "Semicolon", .code = c.KE_KEY_SEMICOLON }, .{ .name = "Equal", .code = c.KE_KEY_EQUAL },
    .{ .name = "A", .code = c.KE_KEY_A }, .{ .name = "B", .code = c.KE_KEY_B },
    .{ .name = "C", .code = c.KE_KEY_C }, .{ .name = "D", .code = c.KE_KEY_D },
    .{ .name = "E", .code = c.KE_KEY_E }, .{ .name = "F", .code = c.KE_KEY_F },
    .{ .name = "G", .code = c.KE_KEY_G }, .{ .name = "H", .code = c.KE_KEY_H },
    .{ .name = "I", .code = c.KE_KEY_I }, .{ .name = "J", .code = c.KE_KEY_J },
    .{ .name = "K", .code = c.KE_KEY_K }, .{ .name = "L", .code = c.KE_KEY_L },
    .{ .name = "M", .code = c.KE_KEY_M }, .{ .name = "N", .code = c.KE_KEY_N },
    .{ .name = "O", .code = c.KE_KEY_O }, .{ .name = "P", .code = c.KE_KEY_P },
    .{ .name = "Q", .code = c.KE_KEY_Q }, .{ .name = "R", .code = c.KE_KEY_R },
    .{ .name = "S", .code = c.KE_KEY_S }, .{ .name = "T", .code = c.KE_KEY_T },
    .{ .name = "U", .code = c.KE_KEY_U }, .{ .name = "V", .code = c.KE_KEY_V },
    .{ .name = "W", .code = c.KE_KEY_W }, .{ .name = "X", .code = c.KE_KEY_X },
    .{ .name = "Y", .code = c.KE_KEY_Y }, .{ .name = "Z", .code = c.KE_KEY_Z },
    .{ .name = "LeftBracket", .code = c.KE_KEY_LEFT_BRACKET },   .{ .name = "BackSlash", .code = c.KE_KEY_BACKSLASH },
    .{ .name = "RightBracket", .code = c.KE_KEY_RIGHT_BRACKET }, .{ .name = "GraveAccent", .code = c.KE_KEY_GRAVE_ACCENT },
    .{ .name = "World1", .code = c.KE_KEY_WORLD_1 },   .{ .name = "World2", .code = c.KE_KEY_WORLD_2 },
    .{ .name = "Escape", .code = c.KE_KEY_ESCAPE },    .{ .name = "Enter", .code = c.KE_KEY_ENTER },
    .{ .name = "Tab", .code = c.KE_KEY_TAB },          .{ .name = "Backspace", .code = c.KE_KEY_BACKSPACE },
    .{ .name = "Insert", .code = c.KE_KEY_INSERT },    .{ .name = "Delete", .code = c.KE_KEY_DELETE },
    .{ .name = "Right", .code = c.KE_KEY_RIGHT },      .{ .name = "Left", .code = c.KE_KEY_LEFT },
    .{ .name = "Down", .code = c.KE_KEY_DOWN },        .{ .name = "Up", .code = c.KE_KEY_UP },
    .{ .name = "PageUp", .code = c.KE_KEY_PAGE_UP },   .{ .name = "PageDown", .code = c.KE_KEY_PAGE_DOWN },
    .{ .name = "Home", .code = c.KE_KEY_HOME },        .{ .name = "End", .code = c.KE_KEY_END },
    .{ .name = "CapsLock", .code = c.KE_KEY_CAPS_LOCK }, .{ .name = "ScrollLock", .code = c.KE_KEY_SCROLL_LOCK },
    .{ .name = "NumLock", .code = c.KE_KEY_NUM_LOCK }, .{ .name = "PrintScreen", .code = c.KE_KEY_PRINT_SCREEN },
    .{ .name = "Pause", .code = c.KE_KEY_PAUSE },
    .{ .name = "F1", .code = c.KE_KEY_F1 },   .{ .name = "F2", .code = c.KE_KEY_F2 },
    .{ .name = "F3", .code = c.KE_KEY_F3 },   .{ .name = "F4", .code = c.KE_KEY_F4 },
    .{ .name = "F5", .code = c.KE_KEY_F5 },   .{ .name = "F6", .code = c.KE_KEY_F6 },
    .{ .name = "F7", .code = c.KE_KEY_F7 },   .{ .name = "F8", .code = c.KE_KEY_F8 },
    .{ .name = "F9", .code = c.KE_KEY_F9 },   .{ .name = "F10", .code = c.KE_KEY_F10 },
    .{ .name = "F11", .code = c.KE_KEY_F11 }, .{ .name = "F12", .code = c.KE_KEY_F12 },
    .{ .name = "F13", .code = c.KE_KEY_F13 }, .{ .name = "F14", .code = c.KE_KEY_F14 },
    .{ .name = "F15", .code = c.KE_KEY_F15 }, .{ .name = "F16", .code = c.KE_KEY_F16 },
    .{ .name = "F17", .code = c.KE_KEY_F17 }, .{ .name = "F18", .code = c.KE_KEY_F18 },
    .{ .name = "F19", .code = c.KE_KEY_F19 }, .{ .name = "F20", .code = c.KE_KEY_F20 },
    .{ .name = "F21", .code = c.KE_KEY_F21 }, .{ .name = "F22", .code = c.KE_KEY_F22 },
    .{ .name = "F23", .code = c.KE_KEY_F23 }, .{ .name = "F24", .code = c.KE_KEY_F24 },
    .{ .name = "F25", .code = c.KE_KEY_F25 },
    .{ .name = "Keypad0", .code = c.KE_KEY_KEYPAD_0 }, .{ .name = "Keypad1", .code = c.KE_KEY_KEYPAD_1 },
    .{ .name = "Keypad2", .code = c.KE_KEY_KEYPAD_2 }, .{ .name = "Keypad3", .code = c.KE_KEY_KEYPAD_3 },
    .{ .name = "Keypad4", .code = c.KE_KEY_KEYPAD_4 }, .{ .name = "Keypad5", .code = c.KE_KEY_KEYPAD_5 },
    .{ .name = "Keypad6", .code = c.KE_KEY_KEYPAD_6 }, .{ .name = "Keypad7", .code = c.KE_KEY_KEYPAD_7 },
    .{ .name = "Keypad8", .code = c.KE_KEY_KEYPAD_8 }, .{ .name = "Keypad9", .code = c.KE_KEY_KEYPAD_9 },
    .{ .name = "KeypadDecimal", .code = c.KE_KEY_KEYPAD_DECIMAL },
    .{ .name = "KeypadDivide", .code = c.KE_KEY_KEYPAD_DIVIDE },
    .{ .name = "KeypadMultiply", .code = c.KE_KEY_KEYPAD_MULTIPLY },
    .{ .name = "KeypadSubtract", .code = c.KE_KEY_KEYPAD_SUBTRACT },
    .{ .name = "KeypadAdd", .code = c.KE_KEY_KEYPAD_ADD },
    .{ .name = "KeypadEnter", .code = c.KE_KEY_KEYPAD_ENTER },
    .{ .name = "KeypadEqual", .code = c.KE_KEY_KEYPAD_EQUAL },
    .{ .name = "ShiftLeft", .code = c.KE_KEY_SHIFT_LEFT },   .{ .name = "ControlLeft", .code = c.KE_KEY_CONTROL_LEFT },
    .{ .name = "AltLeft", .code = c.KE_KEY_ALT_LEFT },       .{ .name = "SuperLeft", .code = c.KE_KEY_SUPER_LEFT },
    .{ .name = "ShiftRight", .code = c.KE_KEY_SHIFT_RIGHT }, .{ .name = "ControlRight", .code = c.KE_KEY_CONTROL_RIGHT },
    .{ .name = "AltRight", .code = c.KE_KEY_ALT_RIGHT },     .{ .name = "SuperRight", .code = c.KE_KEY_SUPER_RIGHT },
    .{ .name = "Menu", .code = c.KE_KEY_MENU },
};

const mouse_table = [_]KeyNameEntry{
    .{ .name = "Left", .code = c.KE_MOUSE_BUTTON_LEFT },
    .{ .name = "Right", .code = c.KE_MOUSE_BUTTON_RIGHT },
    .{ .name = "Middle", .code = c.KE_MOUSE_BUTTON_MIDDLE },
};

fn lookupKey(name: [*c]const u8) c_int {
    if (name == null) return c.KE_KEY_UNKNOWN;
    const n = std.mem.span(name);
    for (key_table) |entry| {
        if (std.mem.eql(u8, entry.name, n)) return entry.code;
    }
    return c.KE_KEY_UNKNOWN;
}

fn lookupMouseButton(name: [*c]const u8) c_int {
    if (name == null) return -1;
    const n = std.mem.span(name);
    for (mouse_table) |entry| {
        if (std.mem.eql(u8, entry.name, n)) return entry.code;
    }
    return -1;
}

/// Unknown type strings fall back to Button rather than failing the load — a
/// typo should not take the whole input map down.
fn parseActionType(s: [*c]const u8) c.ke_action_type {
    if (s == null) return c.KE_ACTION_TYPE_BUTTON;
    const t = std.mem.span(s);
    if (std.mem.eql(u8, t, "Axis1D")) return c.KE_ACTION_TYPE_AXIS1D;
    if (std.mem.eql(u8, t, "Axis2D")) return c.KE_ACTION_TYPE_AXIS2D;
    if (std.mem.eql(u8, t, "Axis3D")) return c.KE_ACTION_TYPE_AXIS3D;
    return c.KE_ACTION_TYPE_BUTTON;
}

// -- internal model ----------------------------------------------------------

const BindingKind = enum(u8) { key, key_pair, key_quad, mouse_button };

const Binding = struct {
    kind: BindingKind,
    // Key codes. k0 doubles as the mouse button id for .mouse_button.
    k0: c_int = 0,
    k1: c_int = 0,
    k2: c_int = 0,
    k3: c_int = 0,
};

const Action = struct {
    name: [action_name_max]u8,
    type: c.ke_action_type,
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
            .type = c.KE_ACTION_TYPE_BUTTON,
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

const State = struct {
    api: c.ke_input_actions,
    actions: ?[*]Action,
    action_count: u32,
    action_capacity: u32,
};

fn stateOf(self: *c.ke_input_actions) *State {
    return @ptrCast(@alignCast(self.handle));
}

// -- dynamic-array helpers ---------------------------------------------------

/// Grows a malloc'd array to hold at least `needed` elements, doubling from
/// `initial`. Returns null on allocation failure, leaving the old buffer intact.
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
        // The old block is released at the capacity it was allocated with,
        // which `capacity` still holds until it is overwritten below.
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

// -- snapshot sampling -------------------------------------------------------

fn isKeyDown(snap: *const c.ke_input_snapshot, key: c_int) bool {
    if (key < 0 or key >= key_bit_count) return false;
    const k: usize = @intCast(key);
    return (snap.keys_down[k / 64] >> @intCast(k % 64)) & 1 != 0;
}

fn isMouseDown(snap: *const c.ke_input_snapshot, button: c_int) bool {
    if (button < 0) return false;
    return (snap.mouse_buttons_down >> @intCast(button)) & 1 != 0;
}

fn axisOf(down: bool) f32 {
    return if (down) 1.0 else 0.0;
}

const Sample = struct { x: f32 = 0, y: f32 = 0, z: f32 = 0 };

/// Returns the binding's contribution plus whether it is contributing at all.
fn sampleBinding(b: *const Binding, snap: *const c.ke_input_snapshot) struct { Sample, bool } {
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

// -- binding parser (from TOML table) ----------------------------------------

/// tomlc99 hands back malloc'd strings the caller must release.
fn freeDatumStr(d: c.toml_datum_t) void {
    if (d.ok != 0 and d.u.s != null) std.c.free(d.u.s);
}

fn parseBindingTable(bt: ?*c.toml_table_t, out: *Binding) bool {
    const kind = c.toml_string_in(bt, "kind");
    if (kind.ok == 0) return false;
    defer freeDatumStr(kind);

    const kind_str = std.mem.span(kind.u.s);

    if (std.mem.eql(u8, kind_str, "key")) {
        const k = c.toml_string_in(bt, "key");
        defer freeDatumStr(k);
        if (k.ok == 0) return false;
        out.* = .{ .kind = .key, .k0 = lookupKey(k.u.s) };
        return true;
    }
    if (std.mem.eql(u8, kind_str, "key_pair")) {
        const neg = c.toml_string_in(bt, "negative");
        const pos = c.toml_string_in(bt, "positive");
        defer freeDatumStr(neg);
        defer freeDatumStr(pos);
        if (neg.ok == 0 or pos.ok == 0) return false;
        out.* = .{ .kind = .key_pair, .k0 = lookupKey(neg.u.s), .k1 = lookupKey(pos.u.s) };
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
        if (up.ok == 0 or down.ok == 0 or left.ok == 0 or right.ok == 0) return false;
        out.* = .{
            .kind = .key_quad,
            .k0 = lookupKey(up.u.s),
            .k1 = lookupKey(down.u.s),
            .k2 = lookupKey(left.u.s),
            .k3 = lookupKey(right.u.s),
        };
        return true;
    }
    if (std.mem.eql(u8, kind_str, "mouse")) {
        const btn = c.toml_string_in(bt, "button");
        defer freeDatumStr(btn);
        if (btn.ok == 0) return false;
        out.* = .{ .kind = .mouse_button, .k0 = lookupMouseButton(btn.u.s) };
        return true;
    }
    return false;
}

// -- vtable: load ------------------------------------------------------------

fn vtLoad(
    self_in: ?*c.ke_input_actions,
    path: [*c]const u8,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null or path == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const s = stateOf(self);
    clearActions(s);

    const fp = std.c.fopen(path, "rb") orelse {
        E.fail(out_error, .not_found, "input file not found", @src());
        return false;
    };
    var errbuf: [200]u8 = undefined;
    const root = c.toml_parse_file(@ptrCast(@alignCast(fp)), &errbuf, errbuf.len);
    _ = std.c.fclose(fp);
    if (root == null) {
        E.fail(out_error, .io, "failed to parse input file", @src());
        return false;
    }
    defer c.toml_free(root);

    // A file with no [action] section is valid and simply defines nothing.
    const action_section = c.toml_table_in(root, "action") orelse return true;

    var i: c_int = 0;
    while (true) : (i += 1) {
        const action_name = c.toml_key_in(action_section, i) orelse break;
        const action_tbl = c.toml_table_in(action_section, action_name) orelse continue;

        if (!ensureActionCapacity(s, s.action_count + 1)) {
            E.fail(out_error, .out_of_memory, "action capacity exceeded", @src());
            return false;
        }
        const act = &s.actions.?[s.action_count];
        act.* = Action.blank();
        copyName(&act.name, std.mem.span(action_name));

        const type_node = c.toml_string_in(action_tbl, "type");
        if (type_node.ok != 0) {
            act.type = parseActionType(type_node.u.s);
            freeDatumStr(type_node);
        }

        if (c.toml_array_in(action_tbl, "bindings")) |bindings_arr| {
            const n = c.toml_array_nelem(bindings_arr);
            var j: c_int = 0;
            while (j < n) : (j += 1) {
                const bt = c.toml_table_at(bindings_arr, j) orelse continue;
                var b: Binding = undefined;
                if (!parseBindingTable(bt, &b)) continue;
                if (!ensureBindingCapacity(act, act.binding_count + 1)) {
                    E.fail(out_error, .out_of_memory, "binding capacity exceeded", @src());
                    return false;
                }
                act.bindings.?[act.binding_count] = b;
                act.binding_count += 1;
            }
        }

        s.action_count += 1;
    }

    return true;
}

// -- vtable: lookup and programmatic registration ----------------------------

fn vtGetActionId(self_in: ?*c.ke_input_actions, name: [*c]const u8) callconv(.c) i32 {
    const self = self_in orelse return -1;
    if (self.handle == null or name == null) return -1;
    return findActionByName(stateOf(self), std.mem.span(name));
}

fn vtAddAction(
    self_in: ?*c.ke_input_actions,
    name: [*c]const u8,
    action_type: c.ke_action_type,
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

fn getActionMut(s: *State, id: i32) ?*Action {
    if (id < 0 or @as(u32, @intCast(id)) >= s.action_count) return null;
    return &s.actions.?[@intCast(id)];
}

fn appendBinding(s: *State, id: i32, b: Binding, out_error: [*c][*c]c.ke_error) bool {
    const a = getActionMut(s, id) orelse {
        E.fail(out_error, .not_found, "action not found", @src());
        return false;
    };
    if (!ensureBindingCapacity(a, a.binding_count + 1)) {
        E.fail(out_error, .out_of_memory, "binding capacity exceeded", @src());
        return false;
    }
    a.bindings.?[a.binding_count] = b;
    a.binding_count += 1;
    return true;
}

fn vtBindKey(
    self_in: ?*c.ke_input_actions,
    action_id: i32,
    key: c.ke_key,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    return appendBinding(stateOf(self), action_id, .{ .kind = .key, .k0 = @intCast(key) }, out_error);
}

fn vtBindMouseButton(
    self_in: ?*c.ke_input_actions,
    action_id: i32,
    button: c.ke_mouse_button,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    return appendBinding(stateOf(self), action_id, .{ .kind = .mouse_button, .k0 = @intCast(button) }, out_error);
}

fn vtBindKeyPair(
    self_in: ?*c.ke_input_actions,
    action_id: i32,
    neg: c.ke_key,
    pos: c.ke_key,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    return appendBinding(
        stateOf(self),
        action_id,
        .{ .kind = .key_pair, .k0 = @intCast(neg), .k1 = @intCast(pos) },
        out_error,
    );
}

fn vtBindKeyQuad(
    self_in: ?*c.ke_input_actions,
    action_id: i32,
    up: c.ke_key,
    down: c.ke_key,
    left: c.ke_key,
    right: c.ke_key,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    return appendBinding(stateOf(self), action_id, .{
        .kind = .key_quad,
        .k0 = @intCast(up),
        .k1 = @intCast(down),
        .k2 = @intCast(left),
        .k3 = @intCast(right),
    }, out_error);
}

// -- vtable: evaluate --------------------------------------------------------

fn vtEvaluate(
    self_in: ?*c.ke_input_actions,
    snapshot_in: ?*const c.ke_input_snapshot,
    on_event: c.ke_input_action_event_func,
    event_ctx: ?*anyopaque,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    const snapshot = snapshot_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const s = stateOf(self);
    if (s.action_count == 0) return true;

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
                if (a.type == c.KE_ACTION_TYPE_BUTTON) {
                    acc.x = 1.0;
                } else {
                    // Strongest contribution per axis wins across bindings.
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
            var ev = std.mem.zeroes(c.ke_input_action_event);
            ev.action_id = id;
            ev.type = a.type;
            ev.phase = if (a.curr_active) c.KE_ACTION_PHASE_STARTED else c.KE_ACTION_PHASE_CANCELED;
            ev.x = acc.x;
            ev.y = acc.y;
            ev.z = acc.z;
            emit(event_ctx, ev);
        }
        if (a.curr_active and a.prev_active and
            a.type != c.KE_ACTION_TYPE_BUTTON and
            (a.prev_x != a.curr_x or a.prev_y != a.curr_y or a.prev_z != a.curr_z))
        {
            var ev = std.mem.zeroes(c.ke_input_action_event);
            ev.action_id = id;
            ev.type = a.type;
            ev.phase = c.KE_ACTION_PHASE_PERFORMED;
            ev.x = acc.x;
            ev.y = acc.y;
            ev.z = acc.z;
            emit(event_ctx, ev);
        }
    }
    return true;
}

// -- vtable: polling ---------------------------------------------------------

fn getAction(self_in: ?*c.ke_input_actions, id: i32) ?*const Action {
    const self = self_in orelse return null;
    if (self.handle == null) return null;
    const s = stateOf(self);
    if (id < 0 or @as(u32, @intCast(id)) >= s.action_count) return null;
    return &s.actions.?[@intCast(id)];
}

fn vtIsActionDown(self_in: ?*c.ke_input_actions, id: i32) callconv(.c) bool {
    const a = getAction(self_in, id) orelse return false;
    return a.curr_active;
}

// Both edge queries branch and return a literal rather than returning the
// `and` expression directly: Zig 0.16 materializes such a computed bool into
// the C-ABI return register as 0xFF instead of 0x01, which a C/C++ caller
// reads back as an invalid bool. Returning constants sidesteps that.
fn vtWasActionPressed(self_in: ?*c.ke_input_actions, id: i32) callconv(.c) bool {
    const a = getAction(self_in, id) orelse return false;
    if (a.curr_active and !a.prev_active) return true;
    return false;
}

fn vtWasActionReleased(self_in: ?*c.ke_input_actions, id: i32) callconv(.c) bool {
    const a = getAction(self_in, id) orelse return false;
    if (!a.curr_active and a.prev_active) return true;
    return false;
}

fn vtGetAxis1d(self_in: ?*c.ke_input_actions, id: i32) callconv(.c) f32 {
    const a = getAction(self_in, id) orelse return 0.0;
    return a.curr_x;
}

fn vtGetAxis2d(self_in: ?*c.ke_input_actions, id: i32, out_x: [*c]f32, out_y: [*c]f32) callconv(.c) void {
    const a = getAction(self_in, id);
    if (out_x != null) out_x.* = if (a) |act| act.curr_x else 0.0;
    if (out_y != null) out_y.* = if (a) |act| act.curr_y else 0.0;
}

fn vtGetAxis3d(
    self_in: ?*c.ke_input_actions,
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

// -- teardown ----------------------------------------------------------------

fn vtDestroy(self_in: ?*c.ke_input_actions) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    clearActions(s);
    if (s.actions) |actions| heap.gpa.free(actions[0..s.action_capacity]);
    heap.gpa.destroy(s);
}

// -- factory -----------------------------------------------------------------

export fn ke_input_actions_create(out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_input_actions_handle {
    const null_handle = std.mem.zeroes(c.ke_input_actions_handle);

    const s = heap.gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return null_handle;
    };
    s.* = std.mem.zeroes(State);

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

    return .{ .ref = &s.api, .destroy = vtDestroy };
}
