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
    try expectSameLayout(abi.c.ke_component_field, translated("ke_component_field"));
    try expectSameLayout(abi.c.ke_component_params, translated("ke_component_params"));
    try expectSameLayout(abi.c.ke_component_meta, translated("ke_component_meta"));
    try expectSameLayout(abi.c.ke_ecs_segment, translated("ke_ecs_segment"));
    try expectSameLayout(abi.c.ke_ecs, translated("ke_ecs"));
    try expectSameLayout(abi.c.ke_ecs_handle, translated("ke_ecs_handle"));
    try expectSameLayout(abi.c.ke_ecs_commands, translated("ke_ecs_commands"));
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_defer_fn")) try expectSameLayout(abi.c.ke_defer_fn, c.ke_defer_fn);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
    if (@hasDecl(c, "ke_query_id")) try expectSameLayout(abi.c.ke_query_id, c.ke_query_id);
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i128, c.KE_QUERY_INVALID), @as(i128, abi.c.KE_QUERY_INVALID));
    try std.testing.expectEqual(@as(i128, c.KE_ENTITY_INVALID), @as(i128, abi.c.KE_ENTITY_INVALID));
    try std.testing.expectEqual(@as(i128, c.KE_COMPONENT_INVALID), @as(i128, abi.c.KE_COMPONENT_INVALID));
}

extern const layout_values: [51]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_component_field),
        @offsetOf(abi.c.ke_component_field, "name"),
        @offsetOf(abi.c.ke_component_field, "type"),
        @offsetOf(abi.c.ke_component_field, "offset"),
        @offsetOf(abi.c.ke_component_field, "size"),
        @offsetOf(abi.c.ke_component_field, "default_value"),
        @offsetOf(abi.c.ke_component_field, "enum_names"),
        @offsetOf(abi.c.ke_component_field, "enum_count"),
        @sizeOf(abi.c.ke_component_params),
        @offsetOf(abi.c.ke_component_params, "name"),
        @offsetOf(abi.c.ke_component_params, "size"),
        @offsetOf(abi.c.ke_component_params, "alignment"),
        @offsetOf(abi.c.ke_component_params, "fields"),
        @offsetOf(abi.c.ke_component_params, "field_count"),
        @sizeOf(abi.c.ke_component_meta),
        @offsetOf(abi.c.ke_component_meta, "cid"),
        @offsetOf(abi.c.ke_component_meta, "size"),
        @offsetOf(abi.c.ke_component_meta, "alignment"),
        @offsetOf(abi.c.ke_component_meta, "fields"),
        @offsetOf(abi.c.ke_component_meta, "field_count"),
        @sizeOf(abi.c.ke_ecs_segment),
        @offsetOf(abi.c.ke_ecs_segment, "entities"),
        @offsetOf(abi.c.ke_ecs_segment, "count"),
        @offsetOf(abi.c.ke_ecs_segment, "columns"),
        @offsetOf(abi.c.ke_ecs_segment, "column_count"),
        @sizeOf(abi.c.ke_ecs),
        @offsetOf(abi.c.ke_ecs, "handle"),
        @offsetOf(abi.c.ke_ecs, "entity_create"),
        @offsetOf(abi.c.ke_ecs, "entity_destroy"),
        @offsetOf(abi.c.ke_ecs, "component_register"),
        @offsetOf(abi.c.ke_ecs, "component_lookup"),
        @offsetOf(abi.c.ke_ecs, "component_add"),
        @offsetOf(abi.c.ke_ecs, "component_remove"),
        @offsetOf(abi.c.ke_ecs, "component_get"),
        @offsetOf(abi.c.ke_ecs, "component_size"),
        @offsetOf(abi.c.ke_ecs, "component_field_write"),
        @offsetOf(abi.c.ke_ecs, "query_register"),
        @offsetOf(abi.c.ke_ecs, "query_resolve"),
        @offsetOf(abi.c.ke_ecs, "entity_reserve"),
        @offsetOf(abi.c.ke_ecs, "entity_materialize"),
        @sizeOf(abi.c.ke_ecs_handle),
        @offsetOf(abi.c.ke_ecs_handle, "ref"),
        @offsetOf(abi.c.ke_ecs_handle, "destroy"),
        @sizeOf(abi.c.ke_ecs_commands),
        @offsetOf(abi.c.ke_ecs_commands, "handle"),
        @offsetOf(abi.c.ke_ecs_commands, "spawn"),
        @offsetOf(abi.c.ke_ecs_commands, "attach"),
        @offsetOf(abi.c.ke_ecs_commands, "detach"),
        @offsetOf(abi.c.ke_ecs_commands, "despawn"),
        @offsetOf(abi.c.ke_ecs_commands, "defer"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
