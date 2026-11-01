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
    if (@hasDecl(c, "ke_log_callback")) try expectSameLayout(abi.c.ke_log_callback, c.ke_log_callback);
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_LOG_LEVEL_TRACE), @as(i64, abi.c.KE_LOG_LEVEL_TRACE));
    try std.testing.expectEqual(@as(i64, c.KE_LOG_LEVEL_DEBUG), @as(i64, abi.c.KE_LOG_LEVEL_DEBUG));
    try std.testing.expectEqual(@as(i64, c.KE_LOG_LEVEL_INFO), @as(i64, abi.c.KE_LOG_LEVEL_INFO));
    try std.testing.expectEqual(@as(i64, c.KE_LOG_LEVEL_WARNING), @as(i64, abi.c.KE_LOG_LEVEL_WARNING));
    try std.testing.expectEqual(@as(i64, c.KE_LOG_LEVEL_ERROR), @as(i64, abi.c.KE_LOG_LEVEL_ERROR));
    try std.testing.expectEqual(@as(i64, c.KE_LOG_LEVEL_CRITICAL), @as(i64, abi.c.KE_LOG_LEVEL_CRITICAL));
}

extern const layout_values: [1]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
