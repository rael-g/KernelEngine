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
    try expectSameLayout(abi.c.ke_input_actions_config, translated("ke_input_actions_config"));
    try expectSameLayout(abi.c.ke_input_actions, translated("ke_input_actions"));
    try expectSameLayout(abi.c.ke_input_actions_handle, translated("ke_input_actions_handle"));
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_defer_fn")) try expectSameLayout(abi.c.ke_defer_fn, c.ke_defer_fn);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
    if (@hasDecl(c, "ke_query_id")) try expectSameLayout(abi.c.ke_query_id, c.ke_query_id);
    if (@hasDecl(c, "ke_schedule_condition_fn")) try expectSameLayout(abi.c.ke_schedule_condition_fn, c.ke_schedule_condition_fn);
    if (@hasDecl(c, "ke_schedule_execute_fn")) try expectSameLayout(abi.c.ke_schedule_execute_fn, c.ke_schedule_execute_fn);
    if (@hasDecl(c, "ke_schedule_set_id")) try expectSameLayout(abi.c.ke_schedule_set_id, c.ke_schedule_set_id);
    if (@hasDecl(c, "ke_schedule_system_id")) try expectSameLayout(abi.c.ke_schedule_system_id, c.ke_schedule_system_id);
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_TYPE_BUTTON), @as(i64, abi.c.KE_ACTION_TYPE_BUTTON));
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_TYPE_AXIS1D), @as(i64, abi.c.KE_ACTION_TYPE_AXIS1D));
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_TYPE_AXIS2D), @as(i64, abi.c.KE_ACTION_TYPE_AXIS2D));
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_TYPE_AXIS3D), @as(i64, abi.c.KE_ACTION_TYPE_AXIS3D));
}

extern const layout_values: [26]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_input_actions_config),
        @offsetOf(abi.c.ke_input_actions_config, "section"),
        @offsetOf(abi.c.ke_input_actions_config, "set"),
        @sizeOf(abi.c.ke_input_actions),
        @offsetOf(abi.c.ke_input_actions, "handle"),
        @offsetOf(abi.c.ke_input_actions, "add_map"),
        @offsetOf(abi.c.ke_input_actions, "get_map_id"),
        @offsetOf(abi.c.ke_input_actions, "set_map_enabled"),
        @offsetOf(abi.c.ke_input_actions, "is_map_enabled"),
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
