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
    try expectSameLayout(abi.ke_variant, translated("ke_variant"));
    try expectSameLayout(abi.ke_variant_table_entry, translated("ke_variant_table_entry"));
    try expectSameLayout(abi.ke_variant_table, translated("ke_variant_table"));
    try expectSameLayout(abi.ke_component_field, translated("ke_component_field"));
    try expectSameLayout(abi.ke_component_params, translated("ke_component_params"));
    try expectSameLayout(abi.ke_component_meta, translated("ke_component_meta"));
    try expectSameLayout(abi.ke_ecs_segment, translated("ke_ecs_segment"));
    try expectSameLayout(abi.ke_ecs, translated("ke_ecs"));
    try expectSameLayout(abi.ke_ecs_handle, translated("ke_ecs_handle"));
    try expectSameLayout(abi.ke_ecs_commands, translated("ke_ecs_commands"));
    try expectSameLayout(abi.ke_component_id, c.ke_component_id);
    try expectSameLayout(abi.ke_defer_fn, c.ke_defer_fn);
    try expectSameLayout(abi.ke_entity, c.ke_entity);
    try expectSameLayout(abi.ke_query_id, c.ke_query_id);
}

test "every enum value is the header's value" {
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_NULL), @as(i64, abi.KE_VARIANT_NULL));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_BOOL), @as(i64, abi.KE_VARIANT_BOOL));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_INT), @as(i64, abi.KE_VARIANT_INT));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_FLOAT), @as(i64, abi.KE_VARIANT_FLOAT));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_STRING), @as(i64, abi.KE_VARIANT_STRING));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_VEC2), @as(i64, abi.KE_VARIANT_VEC2));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_VEC3), @as(i64, abi.KE_VARIANT_VEC3));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_VEC4), @as(i64, abi.KE_VARIANT_VEC4));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_QUAT), @as(i64, abi.KE_VARIANT_QUAT));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_TABLE), @as(i64, abi.KE_VARIANT_TABLE));
}
