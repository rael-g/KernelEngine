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
    try expectSameLayout(abi.c.ke_body2d_component, translated("ke_body2d_component"));
    try expectSameLayout(abi.c.ke_collider2d_component, translated("ke_collider2d_component"));
    if (@hasDecl(c, "ke_body_2d")) try expectSameLayout(abi.c.ke_body_2d, c.ke_body_2d);
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_SHAPE_KIND_2D_BOX), @as(i64, abi.c.KE_SHAPE_KIND_2D_BOX));
    try std.testing.expectEqual(@as(i64, c.KE_SHAPE_KIND_2D_CIRCLE), @as(i64, abi.c.KE_SHAPE_KIND_2D_CIRCLE));
}

extern const layout_values: [18]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_body2d_component),
        @offsetOf(abi.c.ke_body2d_component, "type"),
        @offsetOf(abi.c.ke_body2d_component, "velocity"),
        @offsetOf(abi.c.ke_body2d_component, "angular_velocity"),
        @offsetOf(abi.c.ke_body2d_component, "gravity_scale"),
        @offsetOf(abi.c.ke_body2d_component, "fixed_rotation"),
        @offsetOf(abi.c.ke_body2d_component, "body"),
        @sizeOf(abi.c.ke_collider2d_component),
        @offsetOf(abi.c.ke_collider2d_component, "kind"),
        @offsetOf(abi.c.ke_collider2d_component, "half_extents"),
        @offsetOf(abi.c.ke_collider2d_component, "radius"),
        @offsetOf(abi.c.ke_collider2d_component, "density"),
        @offsetOf(abi.c.ke_collider2d_component, "friction"),
        @offsetOf(abi.c.ke_collider2d_component, "restitution"),
        @offsetOf(abi.c.ke_collider2d_component, "layer"),
        @offsetOf(abi.c.ke_collider2d_component, "mask"),
        @offsetOf(abi.c.ke_collider2d_component, "attached"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
