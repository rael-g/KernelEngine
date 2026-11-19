//! The names a project writes for keys and mouse buttons, as "W", "Space" or "Left", and the codes of the input
//! contract they stand for.

const std = @import("std");
const abi_input = @import("abi_input");

const Entry = struct { name: []const u8, code: c_int };

const key_table = [_]Entry{
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

const mouse_table = [_]Entry{
    .{ .name = "Left", .code = abi_input.c.KE_MOUSE_BUTTON_LEFT },
    .{ .name = "Right", .code = abi_input.c.KE_MOUSE_BUTTON_RIGHT },
    .{ .name = "Middle", .code = abi_input.c.KE_MOUSE_BUTTON_MIDDLE },
};

/// The code of the key named `name`; null for a name no key has.
pub fn key(name: []const u8) ?c_int {
    for (key_table) |entry| if (std.mem.eql(u8, entry.name, name)) return entry.code;
    return null;
}

/// The code of the mouse button named `name`; null for a name no button has.
pub fn mouseButton(name: []const u8) ?c_int {
    for (mouse_table) |entry| if (std.mem.eql(u8, entry.name, name)) return entry.code;
    return null;
}

test "a key and a mouse button are found by the name a project writes" {
    try std.testing.expectEqual(@as(?c_int, abi_input.c.KE_KEY_SPACE), key("Space"));
    try std.testing.expectEqual(@as(?c_int, abi_input.c.KE_MOUSE_BUTTON_LEFT), mouseButton("Left"));
}

test "a name no key or button has is not found" {
    try std.testing.expectEqual(@as(?c_int, null), key("space"));
    try std.testing.expectEqual(@as(?c_int, null), mouseButton("Space"));
}
