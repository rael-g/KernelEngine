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

fn expectSameValue(a: anytype, k: anytype) !void {
    switch (@typeInfo(@TypeOf(a))) {
        .@"struct" => |s| inline for (s.fields) |f| try expectSameValue(@field(a, f.name), @field(k, f.name)),
        .@"union" => {},
        .optional => try std.testing.expectEqualStrings(std.mem.span(k), std.mem.span(a.?)),
        else => try std.testing.expectEqual(@as(@TypeOf(a), k), a),
    }
}

test "every field table lists the header's entries" {
    try std.testing.expectEqual(c.ke_body2d_component_fields.len, abi.ke_body2d_component_fields.len);
    for (abi.ke_body2d_component_fields, c.ke_body2d_component_fields) |a, k| try expectSameValue(a, k);
    try std.testing.expectEqual(c.ke_collider2d_component_fields.len, abi.ke_collider2d_component_fields.len);
    for (abi.ke_collider2d_component_fields, c.ke_collider2d_component_fields) |a, k| try expectSameValue(a, k);
}

test "every constant is the header's value" {
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_BODY2D, abi.KE_COMPONENT_NAME_BODY2D);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_COLLIDER2D, abi.KE_COMPONENT_NAME_COLLIDER2D);
    try std.testing.expectEqual(@as(i128, c.KE_BODY_2D_INVALID), @as(i128, abi.KE_BODY_2D_INVALID));
}
