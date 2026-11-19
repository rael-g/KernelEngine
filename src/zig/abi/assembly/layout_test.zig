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
    try expectSameLayout(abi.c.ke_assembly, translated("ke_assembly"));
    try expectSameLayout(abi.c.ke_assembly_handle, translated("ke_assembly_handle"));
    if (@hasDecl(c, "ke_assembly_report_fn")) try expectSameLayout(abi.c.ke_assembly_report_fn, c.ke_assembly_report_fn);
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_defer_fn")) try expectSameLayout(abi.c.ke_defer_fn, c.ke_defer_fn);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
    if (@hasDecl(c, "ke_log_callback")) try expectSameLayout(abi.c.ke_log_callback, c.ke_log_callback);
    if (@hasDecl(c, "ke_query_id")) try expectSameLayout(abi.c.ke_query_id, c.ke_query_id);
    if (@hasDecl(c, "ke_removal_tracker")) try expectSameLayout(abi.c.ke_removal_tracker, c.ke_removal_tracker);
    if (@hasDecl(c, "ke_schedule_condition_fn")) try expectSameLayout(abi.c.ke_schedule_condition_fn, c.ke_schedule_condition_fn);
    if (@hasDecl(c, "ke_schedule_execute_fn")) try expectSameLayout(abi.c.ke_schedule_execute_fn, c.ke_schedule_execute_fn);
    if (@hasDecl(c, "ke_schedule_set_id")) try expectSameLayout(abi.c.ke_schedule_set_id, c.ke_schedule_set_id);
    if (@hasDecl(c, "ke_schedule_system_id")) try expectSameLayout(abi.c.ke_schedule_system_id, c.ke_schedule_system_id);
    if (@hasDecl(c, "ke_settings_key_func")) try expectSameLayout(abi.c.ke_settings_key_func, c.ke_settings_key_func);
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_ASSEMBLY_FAILURE_UNKNOWN_PART), @as(i64, abi.c.KE_ASSEMBLY_FAILURE_UNKNOWN_PART));
    try std.testing.expectEqual(@as(i64, c.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME), @as(i64, abi.c.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME));
    try std.testing.expectEqual(@as(i64, c.KE_ASSEMBLY_FAILURE_UNSATISFIED), @as(i64, abi.c.KE_ASSEMBLY_FAILURE_UNSATISFIED));
    try std.testing.expectEqual(@as(i64, c.KE_ASSEMBLY_FAILURE_AMBIGUOUS), @as(i64, abi.c.KE_ASSEMBLY_FAILURE_AMBIGUOUS));
    try std.testing.expectEqual(@as(i64, c.KE_ASSEMBLY_FAILURE_WRONG_CONTRACT), @as(i64, abi.c.KE_ASSEMBLY_FAILURE_WRONG_CONTRACT));
    try std.testing.expectEqual(@as(i64, c.KE_ASSEMBLY_FAILURE_CYCLE), @as(i64, abi.c.KE_ASSEMBLY_FAILURE_CYCLE));
    try std.testing.expectEqual(@as(i64, c.KE_ASSEMBLY_FAILURE_UNHOOKED), @as(i64, abi.c.KE_ASSEMBLY_FAILURE_UNHOOKED));
}

test "every constant is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i128, c.KE_RESULT_ASSEMBLY_UNRESOLVED), @as(i128, abi.c.KE_RESULT_ASSEMBLY_UNRESOLVED));
}

extern const layout_values: [18]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_assembly),
        @offsetOf(abi.c.ke_assembly, "handle"),
        @offsetOf(abi.c.ke_assembly, "add_part"),
        @offsetOf(abi.c.ke_assembly, "add_instance"),
        @offsetOf(abi.c.ke_assembly, "add_external"),
        @offsetOf(abi.c.ke_assembly, "bind"),
        @offsetOf(abi.c.ke_assembly, "hook"),
        @offsetOf(abi.c.ke_assembly, "order"),
        @offsetOf(abi.c.ke_assembly, "add_set"),
        @offsetOf(abi.c.ke_assembly, "order_set"),
        @offsetOf(abi.c.ke_assembly, "set_default"),
        @offsetOf(abi.c.ke_assembly, "resolve"),
        @offsetOf(abi.c.ke_assembly, "advance"),
        @offsetOf(abi.c.ke_assembly, "get"),
        @sizeOf(abi.c.ke_assembly_handle),
        @offsetOf(abi.c.ke_assembly_handle, "ref"),
        @offsetOf(abi.c.ke_assembly_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
