const std = @import("std");
const abi = @import("abi");
const c = @import("c");

fn expectSameLayout(comptime A: type, comptime C: type) !void {
    @setEvalBranchQuota(100_000_000);
    if (@typeInfo(C) == .@"opaque") return;
    try std.testing.expectEqual(@sizeOf(C), @sizeOf(A));
    try std.testing.expectEqual(@alignOf(C), @alignOf(A));
    switch (@typeInfo(A)) {
        .@"struct" => |s| inline for (s.fields) |f| {
            try std.testing.expectEqual(@offsetOf(C, f.name), @offsetOf(A, f.name));
            try expectSameLayout(f.type, @FieldType(C, f.name));
        },
        .@"union" => |u| inline for (u.fields) |f| try expectSameLayout(f.type, @FieldType(C, f.name)),
        else => {},
    }
}

fn translated(comptime name: []const u8) type {
    return if (@hasDecl(c, name)) @field(c, name) else @field(c, "struct_" ++ name);
}

test "every record is laid out as the header lays it out" {
    @setEvalBranchQuota(100_000_000);
    try expectSameLayout(abi.c.ke_input_snapshot, translated("ke_input_snapshot"));
    try expectSameLayout(abi.c.ke_input_event, translated("ke_input_event"));
    try expectSameLayout(abi.c.ke_input, translated("ke_input"));
    try expectSameLayout(abi.c.ke_input_handle, translated("ke_input_handle"));
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_KEY_UNKNOWN), @as(i64, abi.c.KE_KEY_UNKNOWN));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_SPACE), @as(i64, abi.c.KE_KEY_SPACE));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_APOSTROPHE), @as(i64, abi.c.KE_KEY_APOSTROPHE));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_COMMA), @as(i64, abi.c.KE_KEY_COMMA));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_MINUS), @as(i64, abi.c.KE_KEY_MINUS));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_PERIOD), @as(i64, abi.c.KE_KEY_PERIOD));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_SLASH), @as(i64, abi.c.KE_KEY_SLASH));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_NUMBER_0), @as(i64, abi.c.KE_KEY_NUMBER_0));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_NUMBER_1), @as(i64, abi.c.KE_KEY_NUMBER_1));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_NUMBER_2), @as(i64, abi.c.KE_KEY_NUMBER_2));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_NUMBER_3), @as(i64, abi.c.KE_KEY_NUMBER_3));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_NUMBER_4), @as(i64, abi.c.KE_KEY_NUMBER_4));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_NUMBER_5), @as(i64, abi.c.KE_KEY_NUMBER_5));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_NUMBER_6), @as(i64, abi.c.KE_KEY_NUMBER_6));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_NUMBER_7), @as(i64, abi.c.KE_KEY_NUMBER_7));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_NUMBER_8), @as(i64, abi.c.KE_KEY_NUMBER_8));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_NUMBER_9), @as(i64, abi.c.KE_KEY_NUMBER_9));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_SEMICOLON), @as(i64, abi.c.KE_KEY_SEMICOLON));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_EQUAL), @as(i64, abi.c.KE_KEY_EQUAL));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_A), @as(i64, abi.c.KE_KEY_A));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_B), @as(i64, abi.c.KE_KEY_B));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_C), @as(i64, abi.c.KE_KEY_C));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_D), @as(i64, abi.c.KE_KEY_D));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_E), @as(i64, abi.c.KE_KEY_E));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F), @as(i64, abi.c.KE_KEY_F));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_G), @as(i64, abi.c.KE_KEY_G));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_H), @as(i64, abi.c.KE_KEY_H));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_I), @as(i64, abi.c.KE_KEY_I));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_J), @as(i64, abi.c.KE_KEY_J));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_K), @as(i64, abi.c.KE_KEY_K));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_L), @as(i64, abi.c.KE_KEY_L));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_M), @as(i64, abi.c.KE_KEY_M));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_N), @as(i64, abi.c.KE_KEY_N));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_O), @as(i64, abi.c.KE_KEY_O));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_P), @as(i64, abi.c.KE_KEY_P));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_Q), @as(i64, abi.c.KE_KEY_Q));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_R), @as(i64, abi.c.KE_KEY_R));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_S), @as(i64, abi.c.KE_KEY_S));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_T), @as(i64, abi.c.KE_KEY_T));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_U), @as(i64, abi.c.KE_KEY_U));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_V), @as(i64, abi.c.KE_KEY_V));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_W), @as(i64, abi.c.KE_KEY_W));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_X), @as(i64, abi.c.KE_KEY_X));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_Y), @as(i64, abi.c.KE_KEY_Y));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_Z), @as(i64, abi.c.KE_KEY_Z));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_LEFT_BRACKET), @as(i64, abi.c.KE_KEY_LEFT_BRACKET));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_BACKSLASH), @as(i64, abi.c.KE_KEY_BACKSLASH));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_RIGHT_BRACKET), @as(i64, abi.c.KE_KEY_RIGHT_BRACKET));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_GRAVE_ACCENT), @as(i64, abi.c.KE_KEY_GRAVE_ACCENT));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_WORLD_1), @as(i64, abi.c.KE_KEY_WORLD_1));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_WORLD_2), @as(i64, abi.c.KE_KEY_WORLD_2));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_ESCAPE), @as(i64, abi.c.KE_KEY_ESCAPE));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_ENTER), @as(i64, abi.c.KE_KEY_ENTER));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_TAB), @as(i64, abi.c.KE_KEY_TAB));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_BACKSPACE), @as(i64, abi.c.KE_KEY_BACKSPACE));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_INSERT), @as(i64, abi.c.KE_KEY_INSERT));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_DELETE), @as(i64, abi.c.KE_KEY_DELETE));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_RIGHT), @as(i64, abi.c.KE_KEY_RIGHT));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_LEFT), @as(i64, abi.c.KE_KEY_LEFT));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_DOWN), @as(i64, abi.c.KE_KEY_DOWN));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_UP), @as(i64, abi.c.KE_KEY_UP));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_PAGE_UP), @as(i64, abi.c.KE_KEY_PAGE_UP));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_PAGE_DOWN), @as(i64, abi.c.KE_KEY_PAGE_DOWN));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_HOME), @as(i64, abi.c.KE_KEY_HOME));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_END), @as(i64, abi.c.KE_KEY_END));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_CAPS_LOCK), @as(i64, abi.c.KE_KEY_CAPS_LOCK));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_SCROLL_LOCK), @as(i64, abi.c.KE_KEY_SCROLL_LOCK));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_NUM_LOCK), @as(i64, abi.c.KE_KEY_NUM_LOCK));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_PRINT_SCREEN), @as(i64, abi.c.KE_KEY_PRINT_SCREEN));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_PAUSE), @as(i64, abi.c.KE_KEY_PAUSE));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F1), @as(i64, abi.c.KE_KEY_F1));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F2), @as(i64, abi.c.KE_KEY_F2));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F3), @as(i64, abi.c.KE_KEY_F3));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F4), @as(i64, abi.c.KE_KEY_F4));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F5), @as(i64, abi.c.KE_KEY_F5));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F6), @as(i64, abi.c.KE_KEY_F6));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F7), @as(i64, abi.c.KE_KEY_F7));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F8), @as(i64, abi.c.KE_KEY_F8));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F9), @as(i64, abi.c.KE_KEY_F9));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F10), @as(i64, abi.c.KE_KEY_F10));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F11), @as(i64, abi.c.KE_KEY_F11));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F12), @as(i64, abi.c.KE_KEY_F12));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F13), @as(i64, abi.c.KE_KEY_F13));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F14), @as(i64, abi.c.KE_KEY_F14));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F15), @as(i64, abi.c.KE_KEY_F15));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F16), @as(i64, abi.c.KE_KEY_F16));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F17), @as(i64, abi.c.KE_KEY_F17));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F18), @as(i64, abi.c.KE_KEY_F18));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F19), @as(i64, abi.c.KE_KEY_F19));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F20), @as(i64, abi.c.KE_KEY_F20));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F21), @as(i64, abi.c.KE_KEY_F21));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F22), @as(i64, abi.c.KE_KEY_F22));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F23), @as(i64, abi.c.KE_KEY_F23));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F24), @as(i64, abi.c.KE_KEY_F24));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_F25), @as(i64, abi.c.KE_KEY_F25));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_0), @as(i64, abi.c.KE_KEY_KEYPAD_0));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_1), @as(i64, abi.c.KE_KEY_KEYPAD_1));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_2), @as(i64, abi.c.KE_KEY_KEYPAD_2));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_3), @as(i64, abi.c.KE_KEY_KEYPAD_3));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_4), @as(i64, abi.c.KE_KEY_KEYPAD_4));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_5), @as(i64, abi.c.KE_KEY_KEYPAD_5));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_6), @as(i64, abi.c.KE_KEY_KEYPAD_6));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_7), @as(i64, abi.c.KE_KEY_KEYPAD_7));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_8), @as(i64, abi.c.KE_KEY_KEYPAD_8));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_9), @as(i64, abi.c.KE_KEY_KEYPAD_9));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_DECIMAL), @as(i64, abi.c.KE_KEY_KEYPAD_DECIMAL));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_DIVIDE), @as(i64, abi.c.KE_KEY_KEYPAD_DIVIDE));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_MULTIPLY), @as(i64, abi.c.KE_KEY_KEYPAD_MULTIPLY));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_SUBTRACT), @as(i64, abi.c.KE_KEY_KEYPAD_SUBTRACT));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_ADD), @as(i64, abi.c.KE_KEY_KEYPAD_ADD));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_ENTER), @as(i64, abi.c.KE_KEY_KEYPAD_ENTER));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_KEYPAD_EQUAL), @as(i64, abi.c.KE_KEY_KEYPAD_EQUAL));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_SHIFT_LEFT), @as(i64, abi.c.KE_KEY_SHIFT_LEFT));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_CONTROL_LEFT), @as(i64, abi.c.KE_KEY_CONTROL_LEFT));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_ALT_LEFT), @as(i64, abi.c.KE_KEY_ALT_LEFT));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_SUPER_LEFT), @as(i64, abi.c.KE_KEY_SUPER_LEFT));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_SHIFT_RIGHT), @as(i64, abi.c.KE_KEY_SHIFT_RIGHT));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_CONTROL_RIGHT), @as(i64, abi.c.KE_KEY_CONTROL_RIGHT));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_ALT_RIGHT), @as(i64, abi.c.KE_KEY_ALT_RIGHT));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_SUPER_RIGHT), @as(i64, abi.c.KE_KEY_SUPER_RIGHT));
    try std.testing.expectEqual(@as(i64, c.KE_KEY_MENU), @as(i64, abi.c.KE_KEY_MENU));
    try std.testing.expectEqual(@as(i64, c.KE_MOUSE_BUTTON_1), @as(i64, abi.c.KE_MOUSE_BUTTON_1));
    try std.testing.expectEqual(@as(i64, c.KE_MOUSE_BUTTON_2), @as(i64, abi.c.KE_MOUSE_BUTTON_2));
    try std.testing.expectEqual(@as(i64, c.KE_MOUSE_BUTTON_3), @as(i64, abi.c.KE_MOUSE_BUTTON_3));
    try std.testing.expectEqual(@as(i64, c.KE_MOUSE_BUTTON_4), @as(i64, abi.c.KE_MOUSE_BUTTON_4));
    try std.testing.expectEqual(@as(i64, c.KE_MOUSE_BUTTON_5), @as(i64, abi.c.KE_MOUSE_BUTTON_5));
    try std.testing.expectEqual(@as(i64, c.KE_MOUSE_BUTTON_6), @as(i64, abi.c.KE_MOUSE_BUTTON_6));
    try std.testing.expectEqual(@as(i64, c.KE_MOUSE_BUTTON_7), @as(i64, abi.c.KE_MOUSE_BUTTON_7));
    try std.testing.expectEqual(@as(i64, c.KE_MOUSE_BUTTON_8), @as(i64, abi.c.KE_MOUSE_BUTTON_8));
    try std.testing.expectEqual(@as(i64, c.KE_MOUSE_BUTTON_LEFT), @as(i64, abi.c.KE_MOUSE_BUTTON_LEFT));
    try std.testing.expectEqual(@as(i64, c.KE_MOUSE_BUTTON_RIGHT), @as(i64, abi.c.KE_MOUSE_BUTTON_RIGHT));
    try std.testing.expectEqual(@as(i64, c.KE_MOUSE_BUTTON_MIDDLE), @as(i64, abi.c.KE_MOUSE_BUTTON_MIDDLE));
    try std.testing.expectEqual(@as(i64, c.KE_INPUT_ACTION_RELEASE), @as(i64, abi.c.KE_INPUT_ACTION_RELEASE));
    try std.testing.expectEqual(@as(i64, c.KE_INPUT_ACTION_PRESS), @as(i64, abi.c.KE_INPUT_ACTION_PRESS));
    try std.testing.expectEqual(@as(i64, c.KE_INPUT_EVENT_NONE), @as(i64, abi.c.KE_INPUT_EVENT_NONE));
    try std.testing.expectEqual(@as(i64, c.KE_INPUT_EVENT_KEY_DOWN), @as(i64, abi.c.KE_INPUT_EVENT_KEY_DOWN));
    try std.testing.expectEqual(@as(i64, c.KE_INPUT_EVENT_KEY_UP), @as(i64, abi.c.KE_INPUT_EVENT_KEY_UP));
    try std.testing.expectEqual(@as(i64, c.KE_INPUT_EVENT_MOUSE_BUTTON_DOWN), @as(i64, abi.c.KE_INPUT_EVENT_MOUSE_BUTTON_DOWN));
    try std.testing.expectEqual(@as(i64, c.KE_INPUT_EVENT_MOUSE_BUTTON_UP), @as(i64, abi.c.KE_INPUT_EVENT_MOUSE_BUTTON_UP));
    try std.testing.expectEqual(@as(i64, c.KE_INPUT_EVENT_MOUSE_MOVE), @as(i64, abi.c.KE_INPUT_EVENT_MOUSE_MOVE));
    try std.testing.expectEqual(@as(i64, c.KE_INPUT_EVENT_MOUSE_SCROLL), @as(i64, abi.c.KE_INPUT_EVENT_MOUSE_SCROLL));
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i128, c.KE_INPUT_MAX_KEYS), @as(i128, abi.c.KE_INPUT_MAX_KEYS));
    try std.testing.expectEqual(@as(i128, c.KE_INPUT_KEY_WORDS), @as(i128, abi.c.KE_INPUT_KEY_WORDS));
    try std.testing.expectEqual(@as(i128, c.KE_INPUT_MAX_MOUSE_BUTTONS), @as(i128, abi.c.KE_INPUT_MAX_MOUSE_BUTTONS));
}

extern const layout_values: [43]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_input_snapshot),
        @offsetOf(abi.c.ke_input_snapshot, "keys_down"),
        @offsetOf(abi.c.ke_input_snapshot, "keys_pressed"),
        @offsetOf(abi.c.ke_input_snapshot, "keys_released"),
        @offsetOf(abi.c.ke_input_snapshot, "mouse_x"),
        @offsetOf(abi.c.ke_input_snapshot, "mouse_y"),
        @offsetOf(abi.c.ke_input_snapshot, "mouse_dx"),
        @offsetOf(abi.c.ke_input_snapshot, "mouse_dy"),
        @offsetOf(abi.c.ke_input_snapshot, "scroll_dx"),
        @offsetOf(abi.c.ke_input_snapshot, "scroll_dy"),
        @offsetOf(abi.c.ke_input_snapshot, "mouse_buttons_down"),
        @offsetOf(abi.c.ke_input_snapshot, "mouse_buttons_pressed"),
        @offsetOf(abi.c.ke_input_snapshot, "mouse_buttons_released"),
        @offsetOf(abi.c.ke_input_snapshot, "events_dropped"),
        @sizeOf(abi.c.ke_input_event),
        @offsetOf(abi.c.ke_input_event, "kind"),
        @offsetOf(abi.c.ke_input_event, "key"),
        @offsetOf(abi.c.ke_input_event, "button"),
        @offsetOf(abi.c.ke_input_event, "scroll"),
        @offsetOf(abi.c.ke_input_event, "position"),
        @offsetOf(abi.c.ke_input_event, "handled"),
        @sizeOf(abi.c.ke_input),
        @offsetOf(abi.c.ke_input, "handle"),
        @offsetOf(abi.c.ke_input, "update"),
        @offsetOf(abi.c.ke_input, "is_key_pressed"),
        @offsetOf(abi.c.ke_input, "is_key_released"),
        @offsetOf(abi.c.ke_input, "is_key_down"),
        @offsetOf(abi.c.ke_input, "get_snapshot"),
        @offsetOf(abi.c.ke_input, "snapshot_is_key_down"),
        @offsetOf(abi.c.ke_input, "snapshot_is_key_pressed"),
        @offsetOf(abi.c.ke_input, "snapshot_is_key_released"),
        @offsetOf(abi.c.ke_input, "snapshot_is_mouse_button_down"),
        @offsetOf(abi.c.ke_input, "snapshot_is_mouse_button_pressed"),
        @offsetOf(abi.c.ke_input, "snapshot_is_mouse_button_released"),
        @offsetOf(abi.c.ke_input, "drain_events"),
        @offsetOf(abi.c.ke_input, "on_key"),
        @offsetOf(abi.c.ke_input, "on_mouse_move"),
        @offsetOf(abi.c.ke_input, "on_mouse_button"),
        @offsetOf(abi.c.ke_input, "on_mouse_scroll"),
        @sizeOf(abi.c.ke_input_handle),
        @offsetOf(abi.c.ke_input_handle, "ref"),
        @offsetOf(abi.c.ke_input_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
