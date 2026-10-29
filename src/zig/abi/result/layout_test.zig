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
}

test "every enum value is the header's value" {
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_GENERAL), @as(i64, abi.KE_RESULT_DOMAIN_GENERAL));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_ASSET), @as(i64, abi.KE_RESULT_DOMAIN_ASSET));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_AUDIO), @as(i64, abi.KE_RESULT_DOMAIN_AUDIO));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_CONFIGURATION), @as(i64, abi.KE_RESULT_DOMAIN_CONFIGURATION));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_ECS), @as(i64, abi.KE_RESULT_DOMAIN_ECS));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_FRAMEWORK), @as(i64, abi.KE_RESULT_DOMAIN_FRAMEWORK));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_INPUT), @as(i64, abi.KE_RESULT_DOMAIN_INPUT));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_LOGGER), @as(i64, abi.KE_RESULT_DOMAIN_LOGGER));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_MATH), @as(i64, abi.KE_RESULT_DOMAIN_MATH));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_PHYSICS), @as(i64, abi.KE_RESULT_DOMAIN_PHYSICS));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_RENDER), @as(i64, abi.KE_RESULT_DOMAIN_RENDER));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_RESOURCE_CACHE), @as(i64, abi.KE_RESULT_DOMAIN_RESOURCE_CACHE));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_RUNTIME), @as(i64, abi.KE_RESULT_DOMAIN_RUNTIME));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_TASK_POOL), @as(i64, abi.KE_RESULT_DOMAIN_TASK_POOL));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_SPATIAL), @as(i64, abi.KE_RESULT_DOMAIN_SPATIAL));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_TEXT), @as(i64, abi.KE_RESULT_DOMAIN_TEXT));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_VIEW), @as(i64, abi.KE_RESULT_DOMAIN_VIEW));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_DOMAIN_WINDOW), @as(i64, abi.KE_RESULT_DOMAIN_WINDOW));
    try std.testing.expectEqual(@as(i64, c.KE_OK), @as(i64, abi.KE_OK));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_GENERAL), @as(i64, abi.KE_RESULT_GENERAL));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_NOT_FOUND), @as(i64, abi.KE_RESULT_NOT_FOUND));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_IO), @as(i64, abi.KE_RESULT_IO));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_OUT_OF_MEMORY), @as(i64, abi.KE_RESULT_OUT_OF_MEMORY));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_INVALID_ARGUMENT), @as(i64, abi.KE_RESULT_INVALID_ARGUMENT));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_NOT_INITIALIZED), @as(i64, abi.KE_RESULT_NOT_INITIALIZED));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_NOT_SUPPORTED), @as(i64, abi.KE_RESULT_NOT_SUPPORTED));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_ALREADY_EXISTS), @as(i64, abi.KE_RESULT_ALREADY_EXISTS));
    try std.testing.expectEqual(@as(i64, c.KE_RESULT_MAX_ENUM), @as(i64, abi.KE_RESULT_MAX_ENUM));
}
