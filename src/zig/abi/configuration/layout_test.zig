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
    try expectSameLayout(abi.ke_config_value, translated("ke_config_value"));
    try expectSameLayout(abi.ke_config_field, translated("ke_config_field"));
    try expectSameLayout(abi.ke_configuration, translated("ke_configuration"));
    try expectSameLayout(abi.ke_configuration_handle, translated("ke_configuration_handle"));
    try expectSameLayout(abi.ke_configuration_source, translated("ke_configuration_source"));
    try expectSameLayout(abi.ke_configuration_source_handle, translated("ke_configuration_source_handle"));
    try expectSameLayout(abi.ke_configuration_change_func, c.ke_configuration_change_func);
    try expectSameLayout(abi.ke_configuration_subscription, c.ke_configuration_subscription);
}

test "every enum value is the header's value" {
    try std.testing.expectEqual(@as(i64, c.KE_CONFIG_INT), @as(i64, abi.KE_CONFIG_INT));
    try std.testing.expectEqual(@as(i64, c.KE_CONFIG_FLOAT), @as(i64, abi.KE_CONFIG_FLOAT));
    try std.testing.expectEqual(@as(i64, c.KE_CONFIG_DOUBLE), @as(i64, abi.KE_CONFIG_DOUBLE));
    try std.testing.expectEqual(@as(i64, c.KE_CONFIG_BOOL), @as(i64, abi.KE_CONFIG_BOOL));
    try std.testing.expectEqual(@as(i64, c.KE_CONFIG_STRING), @as(i64, abi.KE_CONFIG_STRING));
}

test "every constant is the header's value" {
    try std.testing.expectEqual(@as(i128, c.KE_CONFIGURATION_SUBSCRIPTION_NONE), @as(i128, abi.KE_CONFIGURATION_SUBSCRIPTION_NONE));
}
