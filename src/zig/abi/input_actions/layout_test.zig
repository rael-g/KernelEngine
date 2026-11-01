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
    try expectSameLayout(abi.c.ke_input_action_event, translated("ke_input_action_event"));
    try expectSameLayout(abi.c.ke_input_actions, translated("ke_input_actions"));
    try expectSameLayout(abi.c.ke_input_actions_handle, translated("ke_input_actions_handle"));
    if (@hasDecl(c, "ke_input_action_event_func")) try expectSameLayout(abi.c.ke_input_action_event_func, c.ke_input_action_event_func);
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_TYPE_BUTTON), @as(i64, abi.c.KE_ACTION_TYPE_BUTTON));
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_TYPE_AXIS1D), @as(i64, abi.c.KE_ACTION_TYPE_AXIS1D));
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_TYPE_AXIS2D), @as(i64, abi.c.KE_ACTION_TYPE_AXIS2D));
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_TYPE_AXIS3D), @as(i64, abi.c.KE_ACTION_TYPE_AXIS3D));
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_PHASE_STARTED), @as(i64, abi.c.KE_ACTION_PHASE_STARTED));
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_PHASE_PERFORMED), @as(i64, abi.c.KE_ACTION_PHASE_PERFORMED));
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_PHASE_CANCELED), @as(i64, abi.c.KE_ACTION_PHASE_CANCELED));
}

extern const layout_values: [27]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_input_action_event),
        @offsetOf(abi.c.ke_input_action_event, "action_id"),
        @offsetOf(abi.c.ke_input_action_event, "type"),
        @offsetOf(abi.c.ke_input_action_event, "phase"),
        @offsetOf(abi.c.ke_input_action_event, "x"),
        @offsetOf(abi.c.ke_input_action_event, "y"),
        @offsetOf(abi.c.ke_input_action_event, "z"),
        @sizeOf(abi.c.ke_input_actions),
        @offsetOf(abi.c.ke_input_actions, "handle"),
        @offsetOf(abi.c.ke_input_actions, "load"),
        @offsetOf(abi.c.ke_input_actions, "get_action_id"),
        @offsetOf(abi.c.ke_input_actions, "add_action"),
        @offsetOf(abi.c.ke_input_actions, "bind_key"),
        @offsetOf(abi.c.ke_input_actions, "bind_mouse_button"),
        @offsetOf(abi.c.ke_input_actions, "bind_key_pair"),
        @offsetOf(abi.c.ke_input_actions, "bind_key_quad"),
        @offsetOf(abi.c.ke_input_actions, "evaluate"),
        @offsetOf(abi.c.ke_input_actions, "is_action_down"),
        @offsetOf(abi.c.ke_input_actions, "was_action_pressed"),
        @offsetOf(abi.c.ke_input_actions, "was_action_released"),
        @offsetOf(abi.c.ke_input_actions, "get_axis1d"),
        @offsetOf(abi.c.ke_input_actions, "get_axis2d"),
        @offsetOf(abi.c.ke_input_actions, "get_axis3d"),
        @sizeOf(abi.c.ke_input_actions_handle),
        @offsetOf(abi.c.ke_input_actions_handle, "ref"),
        @offsetOf(abi.c.ke_input_actions_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
