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
    try expectSameLayout(abi.c.ke_async_config, translated("ke_async_config"));
    try expectSameLayout(abi.c.ke_async_ctx, translated("ke_async_ctx"));
    try expectSameLayout(abi.c.ke_async, translated("ke_async"));
    try expectSameLayout(abi.c.ke_async_handle, translated("ke_async_handle"));
    if (@hasDecl(c, "ke_async_fn")) try expectSameLayout(abi.c.ke_async_fn, c.ke_async_fn);
}

extern const layout_values: [17]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_async_config),
        @offsetOf(abi.c.ke_async_config, "worker_count"),
        @offsetOf(abi.c.ke_async_config, "submit_capacity"),
        @sizeOf(abi.c.ke_async_ctx),
        @offsetOf(abi.c.ke_async_ctx, "handle"),
        @offsetOf(abi.c.ke_async_ctx, "dep_results"),
        @offsetOf(abi.c.ke_async_ctx, "dep_count"),
        @offsetOf(abi.c.ke_async_ctx, "cancelled"),
        @sizeOf(abi.c.ke_async),
        @offsetOf(abi.c.ke_async, "handle"),
        @offsetOf(abi.c.ke_async, "submit"),
        @offsetOf(abi.c.ke_async, "cancel"),
        @offsetOf(abi.c.ke_async, "drain"),
        @sizeOf(abi.c.ke_async_handle),
        @offsetOf(abi.c.ke_async_handle, "ref"),
        @offsetOf(abi.c.ke_async_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
