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
    try expectSameLayout(abi.c.ke_part_slot, translated("ke_part_slot"));
    try expectSameLayout(abi.c.ke_part_hook, translated("ke_part_hook"));
    try expectSameLayout(abi.c.ke_part_set, translated("ke_part_set"));
    try expectSameLayout(abi.c.ke_part_bound, translated("ke_part_bound"));
    try expectSameLayout(abi.c.ke_part_hooked, translated("ke_part_hooked"));
    try expectSameLayout(abi.c.ke_owner, translated("ke_owner"));
    try expectSameLayout(abi.c.ke_part, translated("ke_part"));
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
    try std.testing.expectEqual(@as(i64, c.KE_PART_CARDINALITY_ONE), @as(i64, abi.c.KE_PART_CARDINALITY_ONE));
    try std.testing.expectEqual(@as(i64, c.KE_PART_CARDINALITY_OPTIONAL), @as(i64, abi.c.KE_PART_CARDINALITY_OPTIONAL));
    try std.testing.expectEqual(@as(i64, c.KE_PART_CARDINALITY_MANY), @as(i64, abi.c.KE_PART_CARDINALITY_MANY));
}

extern const layout_values: [36]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_part_slot),
        @offsetOf(abi.c.ke_part_slot, "name"),
        @offsetOf(abi.c.ke_part_slot, "contract"),
        @offsetOf(abi.c.ke_part_slot, "cardinality"),
        @sizeOf(abi.c.ke_part_hook),
        @offsetOf(abi.c.ke_part_hook, "name"),
        @offsetOf(abi.c.ke_part_hook, "default_set"),
        @sizeOf(abi.c.ke_part_set),
        @offsetOf(abi.c.ke_part_set, "name"),
        @offsetOf(abi.c.ke_part_set, "hook"),
        @offsetOf(abi.c.ke_part_set, "after"),
        @sizeOf(abi.c.ke_part_bound),
        @offsetOf(abi.c.ke_part_bound, "instances"),
        @offsetOf(abi.c.ke_part_bound, "count"),
        @sizeOf(abi.c.ke_part_hooked),
        @offsetOf(abi.c.ke_part_hooked, "schedule"),
        @offsetOf(abi.c.ke_part_hooked, "set"),
        @sizeOf(abi.c.ke_owner),
        @offsetOf(abi.c.ke_owner, "ref"),
        @offsetOf(abi.c.ke_owner, "destroy"),
        @sizeOf(abi.c.ke_part),
        @offsetOf(abi.c.ke_part, "name"),
        @offsetOf(abi.c.ke_part, "provides"),
        @offsetOf(abi.c.ke_part, "provides_count"),
        @offsetOf(abi.c.ke_part, "slots"),
        @offsetOf(abi.c.ke_part, "slot_count"),
        @offsetOf(abi.c.ke_part, "hooks"),
        @offsetOf(abi.c.ke_part, "hook_count"),
        @offsetOf(abi.c.ke_part, "sets"),
        @offsetOf(abi.c.ke_part, "set_count"),
        @offsetOf(abi.c.ke_part, "create"),
        @offsetOf(abi.c.ke_part, "provided"),
        @offsetOf(abi.c.ke_part, "ready"),
        @offsetOf(abi.c.ke_part, "pump"),
        @offsetOf(abi.c.ke_part, "set_log"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
