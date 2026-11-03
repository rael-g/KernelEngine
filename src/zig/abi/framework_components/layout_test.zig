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
    try expectSameLayout(abi.c.ke_hierarchy_component, translated("ke_hierarchy_component"));
    try expectSameLayout(abi.c.ke_name_component, translated("ke_name_component"));
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_HIERARCHY, abi.c.KE_COMPONENT_NAME_HIERARCHY);
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_NAME, abi.c.KE_COMPONENT_NAME_NAME);
}

extern const layout_values: [9]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_hierarchy_component),
        @offsetOf(abi.c.ke_hierarchy_component, "parent"),
        @offsetOf(abi.c.ke_hierarchy_component, "first_child"),
        @offsetOf(abi.c.ke_hierarchy_component, "last_child"),
        @offsetOf(abi.c.ke_hierarchy_component, "next_sibling"),
        @offsetOf(abi.c.ke_hierarchy_component, "prev_sibling"),
        @sizeOf(abi.c.ke_name_component),
        @offsetOf(abi.c.ke_name_component, "name"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
