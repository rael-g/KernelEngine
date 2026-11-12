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
    try expectSameLayout(abi.c.ke_scheduler_config, translated("ke_scheduler_config"));
    try expectSameLayout(abi.c.ke_scheduler, translated("ke_scheduler"));
    try expectSameLayout(abi.c.ke_scheduler_handle, translated("ke_scheduler_handle"));
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_defer_fn")) try expectSameLayout(abi.c.ke_defer_fn, c.ke_defer_fn);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
    if (@hasDecl(c, "ke_query_id")) try expectSameLayout(abi.c.ke_query_id, c.ke_query_id);
    if (@hasDecl(c, "ke_schedule_condition_fn")) try expectSameLayout(abi.c.ke_schedule_condition_fn, c.ke_schedule_condition_fn);
    if (@hasDecl(c, "ke_schedule_execute_fn")) try expectSameLayout(abi.c.ke_schedule_execute_fn, c.ke_schedule_execute_fn);
    if (@hasDecl(c, "ke_schedule_set_id")) try expectSameLayout(abi.c.ke_schedule_set_id, c.ke_schedule_set_id);
    if (@hasDecl(c, "ke_schedule_system_id")) try expectSameLayout(abi.c.ke_schedule_system_id, c.ke_schedule_system_id);
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_SCHEDULER_CADENCE_EVERY_TICK), @as(i64, abi.c.KE_SCHEDULER_CADENCE_EVERY_TICK));
    try std.testing.expectEqual(@as(i64, c.KE_SCHEDULER_CADENCE_FIXED), @as(i64, abi.c.KE_SCHEDULER_CADENCE_FIXED));
    try std.testing.expectEqual(@as(i64, c.KE_SCHEDULER_CADENCE_STARTUP), @as(i64, abi.c.KE_SCHEDULER_CADENCE_STARTUP));
    try std.testing.expectEqual(@as(i64, c.KE_SCHEDULER_CADENCE_SHUTDOWN), @as(i64, abi.c.KE_SCHEDULER_CADENCE_SHUTDOWN));
}

extern const layout_values: [16]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_scheduler_config),
        @offsetOf(abi.c.ke_scheduler_config, "fixed_dt"),
        @offsetOf(abi.c.ke_scheduler_config, "fixed_dt_max_accum"),
        @sizeOf(abi.c.ke_scheduler),
        @offsetOf(abi.c.ke_scheduler, "handle"),
        @offsetOf(abi.c.ke_scheduler, "add_schedule"),
        @offsetOf(abi.c.ke_scheduler, "tick"),
        @offsetOf(abi.c.ke_scheduler, "shutdown"),
        @offsetOf(abi.c.ke_scheduler, "request_exit"),
        @offsetOf(abi.c.ke_scheduler, "exit_requested"),
        @offsetOf(abi.c.ke_scheduler, "sequence"),
        @offsetOf(abi.c.ke_scheduler, "expired"),
        @sizeOf(abi.c.ke_scheduler_handle),
        @offsetOf(abi.c.ke_scheduler_handle, "ref"),
        @offsetOf(abi.c.ke_scheduler_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
