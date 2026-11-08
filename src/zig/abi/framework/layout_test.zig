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
    try expectSameLayout(abi.c.ke_node_handler, translated("ke_node_handler"));
    try expectSameLayout(abi.c.ke_node_type_desc, translated("ke_node_type_desc"));
    try expectSameLayout(abi.c.ke_scene_component_set, translated("ke_scene_component_set"));
    try expectSameLayout(abi.c.ke_scene_component_set_handle, translated("ke_scene_component_set_handle"));
    try expectSameLayout(abi.c.ke_scene_hierarchy_handle, translated("ke_scene_hierarchy_handle"));
    try expectSameLayout(abi.c.ke_node_ctx, translated("ke_node_ctx"));
    try expectSameLayout(abi.c.ke_node_types, translated("ke_node_types"));
    try expectSameLayout(abi.c.ke_node_types_handle, translated("ke_node_types_handle"));
    if (@hasDecl(c, "ke_component_apply_fn")) try expectSameLayout(abi.c.ke_component_apply_fn, c.ke_component_apply_fn);
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_defer_fn")) try expectSameLayout(abi.c.ke_defer_fn, c.ke_defer_fn);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
    if (@hasDecl(c, "ke_node_behaviour_fn")) try expectSameLayout(abi.c.ke_node_behaviour_fn, c.ke_node_behaviour_fn);
    if (@hasDecl(c, "ke_query_id")) try expectSameLayout(abi.c.ke_query_id, c.ke_query_id);
}

extern const layout_values: [49]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_node_handler),
        @offsetOf(abi.c.ke_node_handler, "event"),
        @offsetOf(abi.c.ke_node_handler, "on"),
        @sizeOf(abi.c.ke_node_type_desc),
        @offsetOf(abi.c.ke_node_type_desc, "name"),
        @offsetOf(abi.c.ke_node_type_desc, "fields"),
        @offsetOf(abi.c.ke_node_type_desc, "with"),
        @offsetOf(abi.c.ke_node_type_desc, "with_count"),
        @offsetOf(abi.c.ke_node_type_desc, "ready"),
        @offsetOf(abi.c.ke_node_type_desc, "update"),
        @offsetOf(abi.c.ke_node_type_desc, "fixed_update"),
        @offsetOf(abi.c.ke_node_type_desc, "on"),
        @offsetOf(abi.c.ke_node_type_desc, "on_count"),
        @offsetOf(abi.c.ke_node_type_desc, "user_data"),
        @sizeOf(abi.c.ke_scene_component_set),
        @offsetOf(abi.c.ke_scene_component_set, "handle"),
        @offsetOf(abi.c.ke_scene_component_set, "add"),
        @offsetOf(abi.c.ke_scene_component_set, "register_into"),
        @sizeOf(abi.c.ke_scene_component_set_handle),
        @offsetOf(abi.c.ke_scene_component_set_handle, "ref"),
        @offsetOf(abi.c.ke_scene_component_set_handle, "destroy"),
        @sizeOf(abi.c.ke_scene_hierarchy_handle),
        @offsetOf(abi.c.ke_scene_hierarchy_handle, "ref"),
        @offsetOf(abi.c.ke_scene_hierarchy_handle, "destroy"),
        @sizeOf(abi.c.ke_node_ctx),
        @offsetOf(abi.c.ke_node_ctx, "handle"),
        @offsetOf(abi.c.ke_node_ctx, "self"),
        @offsetOf(abi.c.ke_node_ctx, "fields"),
        @offsetOf(abi.c.ke_node_ctx, "event"),
        @offsetOf(abi.c.ke_node_ctx, "dt"),
        @offsetOf(abi.c.ke_node_ctx, "commands"),
        @offsetOf(abi.c.ke_node_ctx, "next"),
        @offsetOf(abi.c.ke_node_ctx, "get"),
        @offsetOf(abi.c.ke_node_ctx, "parent"),
        @offsetOf(abi.c.ke_node_ctx, "child"),
        @offsetOf(abi.c.ke_node_ctx, "axis"),
        @offsetOf(abi.c.ke_node_ctx, "pressed"),
        @offsetOf(abi.c.ke_node_ctx, "spawn"),
        @offsetOf(abi.c.ke_node_ctx, "destroy"),
        @offsetOf(abi.c.ke_node_ctx, "raise"),
        @sizeOf(abi.c.ke_node_types),
        @offsetOf(abi.c.ke_node_types, "handle"),
        @offsetOf(abi.c.ke_node_types, "register_type"),
        @offsetOf(abi.c.ke_node_types, "register_event"),
        @offsetOf(abi.c.ke_node_types, "spawn"),
        @sizeOf(abi.c.ke_node_types_handle),
        @offsetOf(abi.c.ke_node_types_handle, "ref"),
        @offsetOf(abi.c.ke_node_types_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
