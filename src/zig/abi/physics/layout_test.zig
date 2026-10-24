const std = @import("std");
const abi = @import("abi");
const c = @import("c");

fn expectSameLayout(comptime A: type, comptime C: type) !void {
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
    try expectSameLayout(abi.ke_collision_filter_2d, translated("ke_collision_filter_2d"));
    try expectSameLayout(abi.ke_body_state_2d, translated("ke_body_state_2d"));
    try expectSameLayout(abi.ke_body2d_component, translated("ke_body2d_component"));
    try expectSameLayout(abi.ke_collider2d_component, translated("ke_collider2d_component"));
    try expectSameLayout(abi.ke_physics_2d, translated("ke_physics_2d"));
    try expectSameLayout(abi.ke_physics_2d_handle, translated("ke_physics_2d_handle"));
    try expectSameLayout(abi.ke_body_2d, c.ke_body_2d);
}

test "every enum value is the header's value" {
    try std.testing.expectEqual(@as(i64, c.KE_BODY_TYPE_STATIC), @as(i64, abi.KE_BODY_TYPE_STATIC));
    try std.testing.expectEqual(@as(i64, c.KE_BODY_TYPE_KINEMATIC), @as(i64, abi.KE_BODY_TYPE_KINEMATIC));
    try std.testing.expectEqual(@as(i64, c.KE_BODY_TYPE_DYNAMIC), @as(i64, abi.KE_BODY_TYPE_DYNAMIC));
    try std.testing.expectEqual(@as(i64, c.KE_SHAPE_KIND_2D_BOX), @as(i64, abi.KE_SHAPE_KIND_2D_BOX));
    try std.testing.expectEqual(@as(i64, c.KE_SHAPE_KIND_2D_CIRCLE), @as(i64, abi.KE_SHAPE_KIND_2D_CIRCLE));
}
