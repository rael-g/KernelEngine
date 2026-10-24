const std = @import("std");
const abi = @import("abi");
const c = @import("c");

fn expectSameLayout(comptime A: type, comptime C: type) !void {
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
    try expectSameLayout(abi.ke_component_access, translated("ke_component_access"));
    try expectSameLayout(abi.ke_query_decl, translated("ke_query_decl"));
    try expectSameLayout(abi.ke_runtime_module_params, translated("ke_runtime_module_params"));
    try expectSameLayout(abi.ke_runtime_system_params, translated("ke_runtime_system_params"));
    try expectSameLayout(abi.ke_runtime, translated("ke_runtime"));
    try expectSameLayout(abi.ke_runtime_handle, translated("ke_runtime_handle"));
    try expectSameLayout(abi.ke_system_ctx, translated("ke_system_ctx"));
    try expectSameLayout(abi.ke_module_id, c.ke_module_id);
    try expectSameLayout(abi.ke_module_load_fn, c.ke_module_load_fn);
    try expectSameLayout(abi.ke_module_unload_fn, c.ke_module_unload_fn);
    try expectSameLayout(abi.ke_system_execute_fn, c.ke_system_execute_fn);
    try expectSameLayout(abi.ke_system_id, c.ke_system_id);
}

test "every enum value is the header's value" {
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_STARTUP), @as(i64, abi.KE_PHASE_STARTUP));
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_PRE_UPDATE), @as(i64, abi.KE_PHASE_PRE_UPDATE));
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_FIXED_PRE_UPDATE), @as(i64, abi.KE_PHASE_FIXED_PRE_UPDATE));
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_FIXED_UPDATE), @as(i64, abi.KE_PHASE_FIXED_UPDATE));
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_FIXED_POST_UPDATE), @as(i64, abi.KE_PHASE_FIXED_POST_UPDATE));
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_UPDATE), @as(i64, abi.KE_PHASE_UPDATE));
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_POST_UPDATE), @as(i64, abi.KE_PHASE_POST_UPDATE));
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_RENDER), @as(i64, abi.KE_PHASE_RENDER));
    try std.testing.expectEqual(@as(i64, c.KE_PHASE_SHUTDOWN), @as(i64, abi.KE_PHASE_SHUTDOWN));
    try std.testing.expectEqual(@as(i64, c.KE_ACCESS_READ), @as(i64, abi.KE_ACCESS_READ));
    try std.testing.expectEqual(@as(i64, c.KE_ACCESS_WRITE), @as(i64, abi.KE_ACCESS_WRITE));
}
