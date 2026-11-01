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
    try expectSameLayout(abi.c.ke_resource_cache_params, translated("ke_resource_cache_params"));
    try expectSameLayout(abi.c.ke_resource_cache, translated("ke_resource_cache"));
    try expectSameLayout(abi.c.ke_resource_cache_handle, translated("ke_resource_cache_handle"));
    if (@hasDecl(c, "ke_resource_destroy_func")) try expectSameLayout(abi.c.ke_resource_destroy_func, c.ke_resource_destroy_func);
    if (@hasDecl(c, "ke_resource_handle")) try expectSameLayout(abi.c.ke_resource_handle, c.ke_resource_handle);
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i128, c.KE_RESOURCE_HANDLE_NONE), @as(i128, abi.c.KE_RESOURCE_HANDLE_NONE));
}

extern const layout_values: [15]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_resource_cache_params),
        @offsetOf(abi.c.ke_resource_cache_params, "destroy_fn"),
        @offsetOf(abi.c.ke_resource_cache_params, "destroy_ctx"),
        @sizeOf(abi.c.ke_resource_cache),
        @offsetOf(abi.c.ke_resource_cache, "handle"),
        @offsetOf(abi.c.ke_resource_cache, "register_resource"),
        @offsetOf(abi.c.ke_resource_cache, "retain"),
        @offsetOf(abi.c.ke_resource_cache, "release"),
        @offsetOf(abi.c.ke_resource_cache, "try_get_cached"),
        @offsetOf(abi.c.ke_resource_cache, "cache_insert"),
        @offsetOf(abi.c.ke_resource_cache, "cache_evict"),
        @sizeOf(abi.c.ke_resource_cache_handle),
        @offsetOf(abi.c.ke_resource_cache_handle, "ref"),
        @offsetOf(abi.c.ke_resource_cache_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
