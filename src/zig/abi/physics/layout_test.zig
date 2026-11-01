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
    try expectSameLayout(abi.c.ke_collision_filter_2d, translated("ke_collision_filter_2d"));
    try expectSameLayout(abi.c.ke_body_state_2d, translated("ke_body_state_2d"));
    try expectSameLayout(abi.c.ke_physics_2d, translated("ke_physics_2d"));
    try expectSameLayout(abi.c.ke_physics_2d_handle, translated("ke_physics_2d_handle"));
    if (@hasDecl(c, "ke_body_2d")) try expectSameLayout(abi.c.ke_body_2d, c.ke_body_2d);
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_BODY_TYPE_STATIC), @as(i64, abi.c.KE_BODY_TYPE_STATIC));
    try std.testing.expectEqual(@as(i64, c.KE_BODY_TYPE_KINEMATIC), @as(i64, abi.c.KE_BODY_TYPE_KINEMATIC));
    try std.testing.expectEqual(@as(i64, c.KE_BODY_TYPE_DYNAMIC), @as(i64, abi.c.KE_BODY_TYPE_DYNAMIC));
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i128, c.KE_BODY_2D_INVALID), @as(i128, abi.c.KE_BODY_2D_INVALID));
}

extern const layout_values: [28]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_collision_filter_2d),
        @offsetOf(abi.c.ke_collision_filter_2d, "layer"),
        @offsetOf(abi.c.ke_collision_filter_2d, "mask"),
        @sizeOf(abi.c.ke_body_state_2d),
        @offsetOf(abi.c.ke_body_state_2d, "x"),
        @offsetOf(abi.c.ke_body_state_2d, "y"),
        @offsetOf(abi.c.ke_body_state_2d, "angle"),
        @offsetOf(abi.c.ke_body_state_2d, "velocity_x"),
        @offsetOf(abi.c.ke_body_state_2d, "velocity_y"),
        @offsetOf(abi.c.ke_body_state_2d, "angular_velocity"),
        @sizeOf(abi.c.ke_physics_2d),
        @offsetOf(abi.c.ke_physics_2d, "handle"),
        @offsetOf(abi.c.ke_physics_2d, "set_gravity"),
        @offsetOf(abi.c.ke_physics_2d, "step"),
        @offsetOf(abi.c.ke_physics_2d, "create_body"),
        @offsetOf(abi.c.ke_physics_2d, "destroy_body"),
        @offsetOf(abi.c.ke_physics_2d, "add_box_fixture"),
        @offsetOf(abi.c.ke_physics_2d, "add_circle_fixture"),
        @offsetOf(abi.c.ke_physics_2d, "get_body_state"),
        @offsetOf(abi.c.ke_physics_2d, "set_body_position"),
        @offsetOf(abi.c.ke_physics_2d, "set_body_velocity"),
        @offsetOf(abi.c.ke_physics_2d, "apply_impulse"),
        @offsetOf(abi.c.ke_physics_2d, "set_body_fixed_rotation"),
        @offsetOf(abi.c.ke_physics_2d, "set_body_gravity_scale"),
        @sizeOf(abi.c.ke_physics_2d_handle),
        @offsetOf(abi.c.ke_physics_2d_handle, "ref"),
        @offsetOf(abi.c.ke_physics_2d_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
