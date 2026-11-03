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
    try expectSameLayout(abi.c.ke_vec2, translated("ke_vec2"));
    try expectSameLayout(abi.c.ke_vec3, translated("ke_vec3"));
    try expectSameLayout(abi.c.ke_vec4, translated("ke_vec4"));
    try expectSameLayout(abi.c.ke_quat, translated("ke_quat"));
    try expectSameLayout(abi.c.ke_mat4, translated("ke_mat4"));
    try expectSameLayout(abi.c.ke_transform, translated("ke_transform"));
}

extern const layout_values: [24]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_vec2),
        @offsetOf(abi.c.ke_vec2, "x"),
        @offsetOf(abi.c.ke_vec2, "y"),
        @sizeOf(abi.c.ke_vec3),
        @offsetOf(abi.c.ke_vec3, "x"),
        @offsetOf(abi.c.ke_vec3, "y"),
        @offsetOf(abi.c.ke_vec3, "z"),
        @sizeOf(abi.c.ke_vec4),
        @offsetOf(abi.c.ke_vec4, "x"),
        @offsetOf(abi.c.ke_vec4, "y"),
        @offsetOf(abi.c.ke_vec4, "z"),
        @offsetOf(abi.c.ke_vec4, "w"),
        @sizeOf(abi.c.ke_quat),
        @offsetOf(abi.c.ke_quat, "x"),
        @offsetOf(abi.c.ke_quat, "y"),
        @offsetOf(abi.c.ke_quat, "z"),
        @offsetOf(abi.c.ke_quat, "w"),
        @sizeOf(abi.c.ke_mat4),
        @offsetOf(abi.c.ke_mat4, "m"),
        @sizeOf(abi.c.ke_transform),
        @offsetOf(abi.c.ke_transform, "position"),
        @offsetOf(abi.c.ke_transform, "rotation"),
        @offsetOf(abi.c.ke_transform, "scale"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
