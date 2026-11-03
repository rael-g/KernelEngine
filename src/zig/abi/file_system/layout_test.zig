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
    try expectSameLayout(abi.c.ke_file_stat, translated("ke_file_stat"));
    try expectSameLayout(abi.c.ke_file_system, translated("ke_file_system"));
    try expectSameLayout(abi.c.ke_file_system_handle, translated("ke_file_system_handle"));
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_FILE_KIND_FILE), @as(i64, abi.c.KE_FILE_KIND_FILE));
    try std.testing.expectEqual(@as(i64, c.KE_FILE_KIND_DIRECTORY), @as(i64, abi.c.KE_FILE_KIND_DIRECTORY));
    try std.testing.expectEqual(@as(i64, c.KE_FILE_KIND_OTHER), @as(i64, abi.c.KE_FILE_KIND_OTHER));
}

extern const layout_values: [14]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_file_stat),
        @offsetOf(abi.c.ke_file_stat, "kind"),
        @offsetOf(abi.c.ke_file_stat, "size"),
        @sizeOf(abi.c.ke_file_system),
        @offsetOf(abi.c.ke_file_system, "handle"),
        @offsetOf(abi.c.ke_file_system, "open"),
        @offsetOf(abi.c.ke_file_system, "size"),
        @offsetOf(abi.c.ke_file_system, "read_at"),
        @offsetOf(abi.c.ke_file_system, "close"),
        @offsetOf(abi.c.ke_file_system, "stat"),
        @sizeOf(abi.c.ke_file_system_handle),
        @offsetOf(abi.c.ke_file_system_handle, "ref"),
        @offsetOf(abi.c.ke_file_system_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
