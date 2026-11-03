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
    try expectSameLayout(abi.c.ke_asset_loader, translated("ke_asset_loader"));
    try expectSameLayout(abi.c.ke_asset_loader_handle, translated("ke_asset_loader_handle"));
    if (@hasDecl(c, "ke_load_model_complete_func")) try expectSameLayout(abi.c.ke_load_model_complete_func, c.ke_load_model_complete_func);
    if (@hasDecl(c, "ke_task_func")) try expectSameLayout(abi.c.ke_task_func, c.ke_task_func);
    if (@hasDecl(c, "ke_task_on_complete_func")) try expectSameLayout(abi.c.ke_task_on_complete_func, c.ke_task_on_complete_func);
}

extern const layout_values: [9]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_asset_loader),
        @offsetOf(abi.c.ke_asset_loader, "handle"),
        @offsetOf(abi.c.ke_asset_loader, "load_model"),
        @offsetOf(abi.c.ke_asset_loader, "free_model"),
        @offsetOf(abi.c.ke_asset_loader, "load_model_async"),
        @sizeOf(abi.c.ke_asset_loader_handle),
        @offsetOf(abi.c.ke_asset_loader_handle, "ref"),
        @offsetOf(abi.c.ke_asset_loader_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
