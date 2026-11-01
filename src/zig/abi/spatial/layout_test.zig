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
    try expectSameLayout(abi.c.ke_transform_component, translated("ke_transform_component"));
    try expectSameLayout(abi.c.ke_transform2d_component, translated("ke_transform2d_component"));
    try expectSameLayout(abi.c.ke_world_transform_component, translated("ke_world_transform_component"));
}

extern const layout_values: [12]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_transform_component),
        @offsetOf(abi.c.ke_transform_component, "position"),
        @offsetOf(abi.c.ke_transform_component, "rotation"),
        @offsetOf(abi.c.ke_transform_component, "scale"),
        @sizeOf(abi.c.ke_transform2d_component),
        @offsetOf(abi.c.ke_transform2d_component, "position"),
        @offsetOf(abi.c.ke_transform2d_component, "rotation"),
        @offsetOf(abi.c.ke_transform2d_component, "scale"),
        @offsetOf(abi.c.ke_transform2d_component, "depth"),
        @sizeOf(abi.c.ke_world_transform_component),
        @offsetOf(abi.c.ke_world_transform_component, "matrix"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
