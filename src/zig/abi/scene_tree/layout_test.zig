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
    try expectSameLayout(abi.c.ke_scene_tree, translated("ke_scene_tree"));
    try expectSameLayout(abi.c.ke_scene_tree_handle, translated("ke_scene_tree_handle"));
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_defer_fn")) try expectSameLayout(abi.c.ke_defer_fn, c.ke_defer_fn);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
    if (@hasDecl(c, "ke_query_id")) try expectSameLayout(abi.c.ke_query_id, c.ke_query_id);
}

extern const layout_values: [19]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_scene_tree),
        @offsetOf(abi.c.ke_scene_tree, "handle"),
        @offsetOf(abi.c.ke_scene_tree, "root"),
        @offsetOf(abi.c.ke_scene_tree, "create_node"),
        @offsetOf(abi.c.ke_scene_tree, "create_node_deferred"),
        @offsetOf(abi.c.ke_scene_tree, "destroy_node"),
        @offsetOf(abi.c.ke_scene_tree, "destroy_node_deferred"),
        @offsetOf(abi.c.ke_scene_tree, "destroy_all"),
        @offsetOf(abi.c.ke_scene_tree, "find_node"),
        @offsetOf(abi.c.ke_scene_tree, "parent"),
        @offsetOf(abi.c.ke_scene_tree, "first_child"),
        @offsetOf(abi.c.ke_scene_tree, "next_sibling"),
        @offsetOf(abi.c.ke_scene_tree, "propagate_transforms"),
        @offsetOf(abi.c.ke_scene_tree, "children_first"),
        @offsetOf(abi.c.ke_scene_tree, "hierarchy_generation"),
        @sizeOf(abi.c.ke_scene_tree_handle),
        @offsetOf(abi.c.ke_scene_tree_handle, "ref"),
        @offsetOf(abi.c.ke_scene_tree_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
