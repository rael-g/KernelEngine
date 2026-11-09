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
    try expectSameLayout(abi.c.ke_physics_body2d_module_params, translated("ke_physics_body2d_module_params"));
    try expectSameLayout(abi.c.ke_physics_body2d_module_handle, translated("ke_physics_body2d_module_handle"));
    if (@hasDecl(c, "ke_component_id")) try expectSameLayout(abi.c.ke_component_id, c.ke_component_id);
    if (@hasDecl(c, "ke_defer_fn")) try expectSameLayout(abi.c.ke_defer_fn, c.ke_defer_fn);
    if (@hasDecl(c, "ke_entity")) try expectSameLayout(abi.c.ke_entity, c.ke_entity);
    if (@hasDecl(c, "ke_log_callback")) try expectSameLayout(abi.c.ke_log_callback, c.ke_log_callback);
    if (@hasDecl(c, "ke_module_id")) try expectSameLayout(abi.c.ke_module_id, c.ke_module_id);
    if (@hasDecl(c, "ke_module_load_fn")) try expectSameLayout(abi.c.ke_module_load_fn, c.ke_module_load_fn);
    if (@hasDecl(c, "ke_module_unload_fn")) try expectSameLayout(abi.c.ke_module_unload_fn, c.ke_module_unload_fn);
    if (@hasDecl(c, "ke_query_id")) try expectSameLayout(abi.c.ke_query_id, c.ke_query_id);
    if (@hasDecl(c, "ke_system_execute_fn")) try expectSameLayout(abi.c.ke_system_execute_fn, c.ke_system_execute_fn);
    if (@hasDecl(c, "ke_system_id")) try expectSameLayout(abi.c.ke_system_id, c.ke_system_id);
}

extern const layout_values: [9]c_ulonglong;

test "every size and offset is the one C computes" {
    @setEvalBranchQuota(100_000_000);
    const expected = [_]usize{
        @sizeOf(abi.c.ke_physics_body2d_module_params),
        @offsetOf(abi.c.ke_physics_body2d_module_params, "runtime"),
        @offsetOf(abi.c.ke_physics_body2d_module_params, "ecs"),
        @offsetOf(abi.c.ke_physics_body2d_module_params, "physics"),
        @offsetOf(abi.c.ke_physics_body2d_module_params, "scene_tree"),
        @sizeOf(abi.c.ke_physics_body2d_module_handle),
        @offsetOf(abi.c.ke_physics_body2d_module_handle, "ref"),
        @offsetOf(abi.c.ke_physics_body2d_module_handle, "destroy"),
    };
    for (expected, 0..) |value, at| try std.testing.expectEqual(layout_values[at], value);
}
