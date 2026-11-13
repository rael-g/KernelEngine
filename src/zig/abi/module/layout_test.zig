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
    try expectSameLayout(abi.c.ke_module_targets, translated("ke_module_targets"));
    try expectSameLayout(abi.c.ke_module, translated("ke_module"));
    try expectSameLayout(abi.c.ke_module_handle, translated("ke_module_handle"));
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_defer_fn")) try expectSameLayout(abi.c.ke_defer_fn, c.ke_defer_fn);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
    if (@hasDecl(c, "ke_query_id")) try expectSameLayout(abi.c.ke_query_id, c.ke_query_id);
    if (@hasDecl(c, "ke_removal_tracker")) try expectSameLayout(abi.c.ke_removal_tracker, c.ke_removal_tracker);
    if (@hasDecl(c, "ke_schedule_condition_fn")) try expectSameLayout(abi.c.ke_schedule_condition_fn, c.ke_schedule_condition_fn);
    if (@hasDecl(c, "ke_schedule_execute_fn")) try expectSameLayout(abi.c.ke_schedule_execute_fn, c.ke_schedule_execute_fn);
    if (@hasDecl(c, "ke_schedule_set_id")) try expectSameLayout(abi.c.ke_schedule_set_id, c.ke_schedule_set_id);
    if (@hasDecl(c, "ke_schedule_system_id")) try expectSameLayout(abi.c.ke_schedule_system_id, c.ke_schedule_system_id);
}

extern const layout_values: [22]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_module_targets),
        @offsetOf(abi.c.ke_module_targets, "startup"),
        @offsetOf(abi.c.ke_module_targets, "pre_update"),
        @offsetOf(abi.c.ke_module_targets, "fixed"),
        @offsetOf(abi.c.ke_module_targets, "update"),
        @offsetOf(abi.c.ke_module_targets, "shutdown"),
        @offsetOf(abi.c.ke_module_targets, "startup_set"),
        @offsetOf(abi.c.ke_module_targets, "pre_update_set"),
        @offsetOf(abi.c.ke_module_targets, "fixed_pre_update_set"),
        @offsetOf(abi.c.ke_module_targets, "fixed_update_set"),
        @offsetOf(abi.c.ke_module_targets, "fixed_post_update_set"),
        @offsetOf(abi.c.ke_module_targets, "update_set"),
        @offsetOf(abi.c.ke_module_targets, "post_update_set"),
        @offsetOf(abi.c.ke_module_targets, "shutdown_set"),
        @sizeOf(abi.c.ke_module),
        @offsetOf(abi.c.ke_module, "handle"),
        @offsetOf(abi.c.ke_module, "attach"),
        @offsetOf(abi.c.ke_module, "detach"),
        @sizeOf(abi.c.ke_module_handle),
        @offsetOf(abi.c.ke_module_handle, "ref"),
        @offsetOf(abi.c.ke_module_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
