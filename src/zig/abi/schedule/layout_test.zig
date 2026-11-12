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
    try expectSameLayout(abi.c.ke_schedule_set_desc, translated("ke_schedule_set_desc"));
    try expectSameLayout(abi.c.ke_schedule_system_desc, translated("ke_schedule_system_desc"));
    try expectSameLayout(abi.c.ke_schedule_system_order, translated("ke_schedule_system_order"));
    try expectSameLayout(abi.c.ke_schedule, translated("ke_schedule"));
    try expectSameLayout(abi.c.ke_schedule_handle, translated("ke_schedule_handle"));
    try expectSameLayout(abi.c.ke_schedule_ctx, translated("ke_schedule_ctx"));
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_defer_fn")) try expectSameLayout(abi.c.ke_defer_fn, c.ke_defer_fn);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
    if (@hasDecl(c, "ke_query_id")) try expectSameLayout(abi.c.ke_query_id, c.ke_query_id);
    if (@hasDecl(c, "ke_schedule_condition_fn")) try expectSameLayout(abi.c.ke_schedule_condition_fn, c.ke_schedule_condition_fn);
    if (@hasDecl(c, "ke_schedule_execute_fn")) try expectSameLayout(abi.c.ke_schedule_execute_fn, c.ke_schedule_execute_fn);
    if (@hasDecl(c, "ke_schedule_set_id")) try expectSameLayout(abi.c.ke_schedule_set_id, c.ke_schedule_set_id);
    if (@hasDecl(c, "ke_schedule_system_id")) try expectSameLayout(abi.c.ke_schedule_system_id, c.ke_schedule_system_id);
    if (@hasDecl(c, "ke_task_func")) try expectSameLayout(abi.c.ke_task_func, c.ke_task_func);
    if (@hasDecl(c, "ke_task_on_complete_func")) try expectSameLayout(abi.c.ke_task_on_complete_func, c.ke_task_on_complete_func);
}

extern const layout_values: [40]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_schedule_set_desc),
        @offsetOf(abi.c.ke_schedule_set_desc, "name"),
        @offsetOf(abi.c.ke_schedule_set_desc, "after"),
        @offsetOf(abi.c.ke_schedule_set_desc, "after_count"),
        @sizeOf(abi.c.ke_schedule_system_desc),
        @offsetOf(abi.c.ke_schedule_system_desc, "name"),
        @offsetOf(abi.c.ke_schedule_system_desc, "user_data"),
        @offsetOf(abi.c.ke_schedule_system_desc, "execute"),
        @offsetOf(abi.c.ke_schedule_system_desc, "condition"),
        @offsetOf(abi.c.ke_schedule_system_desc, "queries"),
        @offsetOf(abi.c.ke_schedule_system_desc, "query_count"),
        @offsetOf(abi.c.ke_schedule_system_desc, "access"),
        @offsetOf(abi.c.ke_schedule_system_desc, "access_count"),
        @offsetOf(abi.c.ke_schedule_system_desc, "sets"),
        @offsetOf(abi.c.ke_schedule_system_desc, "set_count"),
        @offsetOf(abi.c.ke_schedule_system_desc, "per_entity"),
        @offsetOf(abi.c.ke_schedule_system_desc, "exclusive"),
        @sizeOf(abi.c.ke_schedule_system_order),
        @offsetOf(abi.c.ke_schedule_system_order, "id"),
        @offsetOf(abi.c.ke_schedule_system_order, "wave"),
        @offsetOf(abi.c.ke_schedule_system_order, "ambiguous"),
        @sizeOf(abi.c.ke_schedule),
        @offsetOf(abi.c.ke_schedule, "handle"),
        @offsetOf(abi.c.ke_schedule, "register_set"),
        @offsetOf(abi.c.ke_schedule, "register_system"),
        @offsetOf(abi.c.ke_schedule, "unregister_system"),
        @offsetOf(abi.c.ke_schedule, "declare_exclusive"),
        @offsetOf(abi.c.ke_schedule, "build"),
        @offsetOf(abi.c.ke_schedule, "describe"),
        @offsetOf(abi.c.ke_schedule, "run"),
        @offsetOf(abi.c.ke_schedule, "commands"),
        @sizeOf(abi.c.ke_schedule_handle),
        @offsetOf(abi.c.ke_schedule_handle, "ref"),
        @offsetOf(abi.c.ke_schedule_handle, "destroy"),
        @sizeOf(abi.c.ke_schedule_ctx),
        @offsetOf(abi.c.ke_schedule_ctx, "handle"),
        @offsetOf(abi.c.ke_schedule_ctx, "commands"),
        @offsetOf(abi.c.ke_schedule_ctx, "view"),
        @offsetOf(abi.c.ke_schedule_ctx, "slice"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
