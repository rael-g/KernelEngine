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
    try expectSameLayout(abi.c.ke_scene_slot_component, translated("ke_scene_slot_component"));
    try expectSameLayout(abi.c.ke_scene_files, translated("ke_scene_files"));
    try expectSameLayout(abi.c.ke_scene_files_handle, translated("ke_scene_files_handle"));
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_defer_fn")) try expectSameLayout(abi.c.ke_defer_fn, c.ke_defer_fn);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
    if (@hasDecl(c, "ke_node_behaviour_fn")) try expectSameLayout(abi.c.ke_node_behaviour_fn, c.ke_node_behaviour_fn);
    if (@hasDecl(c, "ke_query_id")) try expectSameLayout(abi.c.ke_query_id, c.ke_query_id);
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i128, c.KE_SCENE_SLOT_MAX_PATH), @as(i128, abi.c.KE_SCENE_SLOT_MAX_PATH));
    try std.testing.expectEqualStrings(c.KE_COMPONENT_NAME_SCENE_SLOT, abi.c.KE_COMPONENT_NAME_SCENE_SLOT);
}

extern const layout_values: [10]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_scene_slot_component),
        @offsetOf(abi.c.ke_scene_slot_component, "path"),
        @offsetOf(abi.c.ke_scene_slot_component, "loaded"),
        @sizeOf(abi.c.ke_scene_files),
        @offsetOf(abi.c.ke_scene_files, "handle"),
        @offsetOf(abi.c.ke_scene_files, "instantiate"),
        @sizeOf(abi.c.ke_scene_files_handle),
        @offsetOf(abi.c.ke_scene_files_handle, "ref"),
        @offsetOf(abi.c.ke_scene_files_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
