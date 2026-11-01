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
    try expectSameLayout(abi.c.ke_script_host, translated("ke_script_host"));
    try expectSameLayout(abi.c.ke_script_host_handle, translated("ke_script_host_handle"));
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_defer_fn")) try expectSameLayout(abi.c.ke_defer_fn, c.ke_defer_fn);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
    if (@hasDecl(c, "ke_query_id")) try expectSameLayout(abi.c.ke_query_id, c.ke_query_id);
    if (@hasDecl(c, "ke_script_type_id")) try expectSameLayout(abi.c.ke_script_type_id, c.ke_script_type_id);
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_SCRIPT_REACH_SELF), @as(i64, abi.c.KE_SCRIPT_REACH_SELF));
    try std.testing.expectEqual(@as(i64, c.KE_SCRIPT_REACH_ANY), @as(i64, abi.c.KE_SCRIPT_REACH_ANY));
    try std.testing.expectEqual(@as(i64, c.KE_SCRIPT_RESOLVE_FOUND), @as(i64, abi.c.KE_SCRIPT_RESOLVE_FOUND));
    try std.testing.expectEqual(@as(i64, c.KE_SCRIPT_RESOLVE_NONE), @as(i64, abi.c.KE_SCRIPT_RESOLVE_NONE));
    try std.testing.expectEqual(@as(i64, c.KE_SCRIPT_RESOLVE_AMBIGUOUS), @as(i64, abi.c.KE_SCRIPT_RESOLVE_AMBIGUOUS));
    try std.testing.expectEqual(@as(i64, c.KE_SCRIPT_BORROW_DESCENDANT), @as(i64, abi.c.KE_SCRIPT_BORROW_DESCENDANT));
    try std.testing.expectEqual(@as(i64, c.KE_SCRIPT_BORROW_ANCESTOR), @as(i64, abi.c.KE_SCRIPT_BORROW_ANCESTOR));
    try std.testing.expectEqual(@as(i64, c.KE_SCRIPT_BORROW_ANYWHERE), @as(i64, abi.c.KE_SCRIPT_BORROW_ANYWHERE));
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i128, c.KE_SCRIPT_TYPE_NONE), @as(i128, abi.c.KE_SCRIPT_TYPE_NONE));
}

extern const layout_values: [20]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_script_host),
        @offsetOf(abi.c.ke_script_host, "handle"),
        @offsetOf(abi.c.ke_script_host, "register_type"),
        @offsetOf(abi.c.ke_script_host, "type_lookup"),
        @offsetOf(abi.c.ke_script_host, "type_components"),
        @offsetOf(abi.c.ke_script_host, "type_reach"),
        @offsetOf(abi.c.ke_script_host, "type_tag"),
        @offsetOf(abi.c.ke_script_host, "type_tag_group"),
        @offsetOf(abi.c.ke_script_host, "bind"),
        @offsetOf(abi.c.ke_script_host, "unbind"),
        @offsetOf(abi.c.ke_script_host, "bind_deferred"),
        @offsetOf(abi.c.ke_script_host, "unbind_deferred"),
        @offsetOf(abi.c.ke_script_host, "instance_of"),
        @offsetOf(abi.c.ke_script_host, "instance_count"),
        @offsetOf(abi.c.ke_script_host, "instances"),
        @offsetOf(abi.c.ke_script_host, "resolve"),
        @sizeOf(abi.c.ke_script_host_handle),
        @offsetOf(abi.c.ke_script_host_handle, "ref"),
        @offsetOf(abi.c.ke_script_host_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
