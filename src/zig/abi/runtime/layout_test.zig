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
    try expectSameLayout(abi.c.ke_component_access, translated("ke_component_access"));
    try expectSameLayout(abi.c.ke_query_decl, translated("ke_query_decl"));
    try expectSameLayout(abi.c.ke_runtime_module_params, translated("ke_runtime_module_params"));
    try expectSameLayout(abi.c.ke_runtime_system_params, translated("ke_runtime_system_params"));
    try expectSameLayout(abi.c.ke_runtime_params, translated("ke_runtime_params"));
    try expectSameLayout(abi.c.ke_runtime, translated("ke_runtime"));
    try expectSameLayout(abi.c.ke_runtime_handle, translated("ke_runtime_handle"));
    try expectSameLayout(abi.c.ke_system_ctx, translated("ke_system_ctx"));
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_defer_fn")) try expectSameLayout(abi.c.ke_defer_fn, c.ke_defer_fn);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
    if (@hasDecl(c, "ke_module_id")) try expectSameLayout(abi.c.ke_module_id, c.ke_module_id);
    if (@hasDecl(c, "ke_module_load_fn")) try expectSameLayout(abi.c.ke_module_load_fn, c.ke_module_load_fn);
    if (@hasDecl(c, "ke_module_unload_fn")) try expectSameLayout(abi.c.ke_module_unload_fn, c.ke_module_unload_fn);
    if (@hasDecl(c, "ke_query_id")) try expectSameLayout(abi.c.ke_query_id, c.ke_query_id);
    if (@hasDecl(c, "ke_system_execute_fn")) try expectSameLayout(abi.c.ke_system_execute_fn, c.ke_system_execute_fn);
    if (@hasDecl(c, "ke_system_id")) try expectSameLayout(abi.c.ke_system_id, c.ke_system_id);
    if (@hasDecl(c, "ke_task_func")) try expectSameLayout(abi.c.ke_task_func, c.ke_task_func);
    if (@hasDecl(c, "ke_task_on_complete_func")) try expectSameLayout(abi.c.ke_task_on_complete_func, c.ke_task_on_complete_func);
}

test "every enum value is the header's value" {
    @setEvalBranchQuota(100_000_000);
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_STARTUP), @as(i64, abi.c.KE_PHASE_STARTUP));
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_PRE_UPDATE), @as(i64, abi.c.KE_PHASE_PRE_UPDATE));
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_FIXED_PRE_UPDATE), @as(i64, abi.c.KE_PHASE_FIXED_PRE_UPDATE));
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_FIXED_UPDATE), @as(i64, abi.c.KE_PHASE_FIXED_UPDATE));
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_FIXED_POST_UPDATE), @as(i64, abi.c.KE_PHASE_FIXED_POST_UPDATE));
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_UPDATE), @as(i64, abi.c.KE_PHASE_UPDATE));
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_POST_UPDATE), @as(i64, abi.c.KE_PHASE_POST_UPDATE));
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_RENDER), @as(i64, abi.c.KE_PHASE_RENDER));
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_SHUTDOWN), @as(i64, abi.c.KE_PHASE_SHUTDOWN));
    try std.testing.expectEqual(@as(i64, c.KE_ACCESS_READ), @as(i64, abi.c.KE_ACCESS_READ));
    try std.testing.expectEqual(@as(i64, c.KE_ACCESS_WRITE), @as(i64, abi.c.KE_ACCESS_WRITE));
}

extern const layout_values: [53]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_component_access),
        @offsetOf(abi.c.ke_component_access, "cid"),
        @offsetOf(abi.c.ke_component_access, "access"),
        @sizeOf(abi.c.ke_query_decl),
        @offsetOf(abi.c.ke_query_decl, "terms"),
        @offsetOf(abi.c.ke_query_decl, "term_count"),
        @sizeOf(abi.c.ke_runtime_module_params),
        @offsetOf(abi.c.ke_runtime_module_params, "name"),
        @offsetOf(abi.c.ke_runtime_module_params, "user_data"),
        @offsetOf(abi.c.ke_runtime_module_params, "on_load"),
        @offsetOf(abi.c.ke_runtime_module_params, "on_unload"),
        @sizeOf(abi.c.ke_runtime_system_params),
        @offsetOf(abi.c.ke_runtime_system_params, "name"),
        @offsetOf(abi.c.ke_runtime_system_params, "phase"),
        @offsetOf(abi.c.ke_runtime_system_params, "user_data"),
        @offsetOf(abi.c.ke_runtime_system_params, "execute"),
        @offsetOf(abi.c.ke_runtime_system_params, "queries"),
        @offsetOf(abi.c.ke_runtime_system_params, "query_count"),
        @offsetOf(abi.c.ke_runtime_system_params, "access_list"),
        @offsetOf(abi.c.ke_runtime_system_params, "access_count"),
        @offsetOf(abi.c.ke_runtime_system_params, "per_entity"),
        @offsetOf(abi.c.ke_runtime_system_params, "after"),
        @offsetOf(abi.c.ke_runtime_system_params, "after_count"),
        @offsetOf(abi.c.ke_runtime_system_params, "before"),
        @offsetOf(abi.c.ke_runtime_system_params, "before_count"),
        @offsetOf(abi.c.ke_runtime_system_params, "exclusive"),
        @sizeOf(abi.c.ke_runtime_params),
        @offsetOf(abi.c.ke_runtime_params, "fixed_dt"),
        @offsetOf(abi.c.ke_runtime_params, "fixed_dt_max_accum"),
        @offsetOf(abi.c.ke_runtime_params, "max_systems_per_phase"),
        @sizeOf(abi.c.ke_runtime),
        @offsetOf(abi.c.ke_runtime, "handle"),
        @offsetOf(abi.c.ke_runtime, "register_module"),
        @offsetOf(abi.c.ke_runtime, "register_system"),
        @offsetOf(abi.c.ke_runtime, "unregister_system"),
        @offsetOf(abi.c.ke_runtime, "last_system"),
        @offsetOf(abi.c.ke_runtime, "declare_exclusive"),
        @offsetOf(abi.c.ke_runtime, "declare_self_ordered"),
        @offsetOf(abi.c.ke_runtime, "check_order"),
        @offsetOf(abi.c.ke_runtime, "tick"),
        @offsetOf(abi.c.ke_runtime, "flush_render"),
        @offsetOf(abi.c.ke_runtime, "unload_modules"),
        @offsetOf(abi.c.ke_runtime, "request_exit"),
        @offsetOf(abi.c.ke_runtime, "exit_requested"),
        @sizeOf(abi.c.ke_runtime_handle),
        @offsetOf(abi.c.ke_runtime_handle, "ref"),
        @offsetOf(abi.c.ke_runtime_handle, "destroy"),
        @sizeOf(abi.c.ke_system_ctx),
        @offsetOf(abi.c.ke_system_ctx, "handle"),
        @offsetOf(abi.c.ke_system_ctx, "commands"),
        @offsetOf(abi.c.ke_system_ctx, "view"),
        @offsetOf(abi.c.ke_system_ctx, "slice"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
