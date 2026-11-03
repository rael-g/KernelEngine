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
    try expectSameLayout(abi.c.ke_variant, translated("ke_variant"));
    try expectSameLayout(abi.c.ke_variant_table_entry, translated("ke_variant_table_entry"));
    try expectSameLayout(abi.c.ke_variant_table, translated("ke_variant_table"));
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_NULL), @as(i64, abi.c.KE_VARIANT_NULL));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_BOOL), @as(i64, abi.c.KE_VARIANT_BOOL));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_INT), @as(i64, abi.c.KE_VARIANT_INT));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_FLOAT), @as(i64, abi.c.KE_VARIANT_FLOAT));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_STRING), @as(i64, abi.c.KE_VARIANT_STRING));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_VEC2), @as(i64, abi.c.KE_VARIANT_VEC2));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_VEC3), @as(i64, abi.c.KE_VARIANT_VEC3));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_VEC4), @as(i64, abi.c.KE_VARIANT_VEC4));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_QUAT), @as(i64, abi.c.KE_VARIANT_QUAT));
    try std.testing.expectEqual(@as(i64, c.KE_VARIANT_TABLE), @as(i64, abi.c.KE_VARIANT_TABLE));
}

extern const layout_values: [10]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_variant),
        @offsetOf(abi.c.ke_variant, "type"),
        @sizeOf(abi.c.ke_variant_table_entry),
        @offsetOf(abi.c.ke_variant_table_entry, "key"),
        @offsetOf(abi.c.ke_variant_table_entry, "value"),
        @offsetOf(abi.c.ke_variant_table_entry, "consumed"),
        @sizeOf(abi.c.ke_variant_table),
        @offsetOf(abi.c.ke_variant_table, "count"),
        @offsetOf(abi.c.ke_variant_table, "entries"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
