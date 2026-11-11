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
    try expectSameLayout(abi.c.ke_id_access, translated("ke_id_access"));
    try expectSameLayout(abi.c.ke_query_desc, translated("ke_query_desc"));
    try expectSameLayout(abi.c.ke_phase_desc, translated("ke_phase_desc"));
    try expectSameLayout(abi.c.ke_set_desc, translated("ke_set_desc"));
    try expectSameLayout(abi.c.ke_system_desc, translated("ke_system_desc"));
    try expectSameLayout(abi.c.ke_system_order, translated("ke_system_order"));
    try expectSameLayout(abi.c.ke_scheduler_config, translated("ke_scheduler_config"));
    try expectSameLayout(abi.c.ke_scheduler, translated("ke_scheduler"));
    try expectSameLayout(abi.c.ke_scheduler_handle, translated("ke_scheduler_handle"));
    try expectSameLayout(abi.c.ke_scheduler_ctx, translated("ke_scheduler_ctx"));
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_defer_fn")) try expectSameLayout(abi.c.ke_defer_fn, c.ke_defer_fn);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
    if (@hasDecl(c, "ke_phase_id")) try expectSameLayout(abi.c.ke_phase_id, c.ke_phase_id);
    if (@hasDecl(c, "ke_query_id")) try expectSameLayout(abi.c.ke_query_id, c.ke_query_id);
    if (@hasDecl(c, "ke_scheduler_execute_fn")) try expectSameLayout(abi.c.ke_scheduler_execute_fn, c.ke_scheduler_execute_fn);
    if (@hasDecl(c, "ke_scheduler_system_id")) try expectSameLayout(abi.c.ke_scheduler_system_id, c.ke_scheduler_system_id);
    if (@hasDecl(c, "ke_set_id")) try expectSameLayout(abi.c.ke_set_id, c.ke_set_id);
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_SCHEDULER_ACCESS_READ), @as(i64, abi.c.KE_SCHEDULER_ACCESS_READ));
    try std.testing.expectEqual(@as(i64, c.KE_SCHEDULER_ACCESS_WRITE), @as(i64, abi.c.KE_SCHEDULER_ACCESS_WRITE));
    try std.testing.expectEqual(@as(i64, c.KE_LIFETIME_PERSISTENT), @as(i64, abi.c.KE_LIFETIME_PERSISTENT));
    try std.testing.expectEqual(@as(i64, c.KE_LIFETIME_PHASE), @as(i64, abi.c.KE_LIFETIME_PHASE));
}

extern const layout_values: [53]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_id_access),
        @offsetOf(abi.c.ke_id_access, "id"),
        @offsetOf(abi.c.ke_id_access, "access"),
        @sizeOf(abi.c.ke_query_desc),
        @offsetOf(abi.c.ke_query_desc, "terms"),
        @offsetOf(abi.c.ke_query_desc, "term_count"),
        @sizeOf(abi.c.ke_phase_desc),
        @offsetOf(abi.c.ke_phase_desc, "name"),
        @sizeOf(abi.c.ke_set_desc),
        @offsetOf(abi.c.ke_set_desc, "name"),
        @offsetOf(abi.c.ke_set_desc, "phase"),
        @offsetOf(abi.c.ke_set_desc, "after"),
        @offsetOf(abi.c.ke_set_desc, "after_count"),
        @sizeOf(abi.c.ke_system_desc),
        @offsetOf(abi.c.ke_system_desc, "name"),
        @offsetOf(abi.c.ke_system_desc, "phase"),
        @offsetOf(abi.c.ke_system_desc, "user_data"),
        @offsetOf(abi.c.ke_system_desc, "execute"),
        @offsetOf(abi.c.ke_system_desc, "queries"),
        @offsetOf(abi.c.ke_system_desc, "query_count"),
        @offsetOf(abi.c.ke_system_desc, "access"),
        @offsetOf(abi.c.ke_system_desc, "access_count"),
        @offsetOf(abi.c.ke_system_desc, "sets"),
        @offsetOf(abi.c.ke_system_desc, "set_count"),
        @offsetOf(abi.c.ke_system_desc, "per_entity"),
        @offsetOf(abi.c.ke_system_desc, "exclusive"),
        @sizeOf(abi.c.ke_system_order),
        @offsetOf(abi.c.ke_system_order, "id"),
        @offsetOf(abi.c.ke_system_order, "wave"),
        @offsetOf(abi.c.ke_system_order, "culled"),
        @sizeOf(abi.c.ke_scheduler_config),
        @offsetOf(abi.c.ke_scheduler_config, "reserved"),
        @sizeOf(abi.c.ke_scheduler),
        @offsetOf(abi.c.ke_scheduler, "handle"),
        @offsetOf(abi.c.ke_scheduler, "register_phase"),
        @offsetOf(abi.c.ke_scheduler, "register_set"),
        @offsetOf(abi.c.ke_scheduler, "register_system"),
        @offsetOf(abi.c.ke_scheduler, "unregister_system"),
        @offsetOf(abi.c.ke_scheduler, "declare_lifetime"),
        @offsetOf(abi.c.ke_scheduler, "declare_exclusive"),
        @offsetOf(abi.c.ke_scheduler, "build"),
        @offsetOf(abi.c.ke_scheduler, "describe_phase"),
        @offsetOf(abi.c.ke_scheduler, "run"),
        @offsetOf(abi.c.ke_scheduler, "commands"),
        @sizeOf(abi.c.ke_scheduler_handle),
        @offsetOf(abi.c.ke_scheduler_handle, "ref"),
        @offsetOf(abi.c.ke_scheduler_handle, "destroy"),
        @sizeOf(abi.c.ke_scheduler_ctx),
        @offsetOf(abi.c.ke_scheduler_ctx, "handle"),
        @offsetOf(abi.c.ke_scheduler_ctx, "commands"),
        @offsetOf(abi.c.ke_scheduler_ctx, "view"),
        @offsetOf(abi.c.ke_scheduler_ctx, "slice"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
