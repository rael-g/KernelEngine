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
    try expectSameLayout(abi.c.ke_configuration, translated("ke_configuration"));
    try expectSameLayout(abi.c.ke_configuration_handle, translated("ke_configuration_handle"));
    try expectSameLayout(abi.c.ke_configuration_source, translated("ke_configuration_source"));
    try expectSameLayout(abi.c.ke_configuration_source_handle, translated("ke_configuration_source_handle"));
    if (@hasDecl(c, "ke_configuration_change_func")) try expectSameLayout(abi.c.ke_configuration_change_func, c.ke_configuration_change_func);
    if (@hasDecl(c, "ke_configuration_child_func")) try expectSameLayout(abi.c.ke_configuration_child_func, c.ke_configuration_child_func);
    if (@hasDecl(c, "ke_configuration_subscription")) try expectSameLayout(abi.c.ke_configuration_subscription, c.ke_configuration_subscription);
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i128, c.KE_CONFIGURATION_SUBSCRIPTION_NONE), @as(i128, abi.c.KE_CONFIGURATION_SUBSCRIPTION_NONE));
}

extern const layout_values: [23]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_configuration),
        @offsetOf(abi.c.ke_configuration, "handle"),
        @offsetOf(abi.c.ke_configuration, "get_int"),
        @offsetOf(abi.c.ke_configuration, "get_double"),
        @offsetOf(abi.c.ke_configuration, "get_bool"),
        @offsetOf(abi.c.ke_configuration, "get_string"),
        @offsetOf(abi.c.ke_configuration, "set_int"),
        @offsetOf(abi.c.ke_configuration, "set_double"),
        @offsetOf(abi.c.ke_configuration, "set_bool"),
        @offsetOf(abi.c.ke_configuration, "set_string"),
        @offsetOf(abi.c.ke_configuration, "subscribe"),
        @offsetOf(abi.c.ke_configuration, "unsubscribe"),
        @offsetOf(abi.c.ke_configuration, "for_each_child"),
        @sizeOf(abi.c.ke_configuration_handle),
        @offsetOf(abi.c.ke_configuration_handle, "ref"),
        @offsetOf(abi.c.ke_configuration_handle, "destroy"),
        @sizeOf(abi.c.ke_configuration_source),
        @offsetOf(abi.c.ke_configuration_source, "handle"),
        @offsetOf(abi.c.ke_configuration_source, "load"),
        @sizeOf(abi.c.ke_configuration_source_handle),
        @offsetOf(abi.c.ke_configuration_source_handle, "ref"),
        @offsetOf(abi.c.ke_configuration_source_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
