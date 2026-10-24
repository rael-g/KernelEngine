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
    try expectSameLayout(abi.ke_hierarchy_component, translated("ke_hierarchy_component"));
    try expectSameLayout(abi.ke_name_component, translated("ke_name_component"));
    try expectSameLayout(abi.ke_input_action_event, translated("ke_input_action_event"));
    try expectSameLayout(abi.ke_world_params, translated("ke_world_params"));
    try expectSameLayout(abi.ke_signal_delivery, translated("ke_signal_delivery"));
    try expectSameLayout(abi.ke_input_actions, translated("ke_input_actions"));
    try expectSameLayout(abi.ke_input_actions_handle, translated("ke_input_actions_handle"));
    try expectSameLayout(abi.ke_world, translated("ke_world"));
    try expectSameLayout(abi.ke_world_handle, translated("ke_world_handle"));
    try expectSameLayout(abi.ke_scene_component_set, translated("ke_scene_component_set"));
    try expectSameLayout(abi.ke_scene_component_set_handle, translated("ke_scene_component_set_handle"));
    try expectSameLayout(abi.ke_scene_hierarchy_handle, translated("ke_scene_hierarchy_handle"));
    try expectSameLayout(abi.ke_scene_loader, translated("ke_scene_loader"));
    try expectSameLayout(abi.ke_scene_loader_handle, translated("ke_scene_loader_handle"));
    try expectSameLayout(abi.ke_scene_tree, translated("ke_scene_tree"));
    try expectSameLayout(abi.ke_scene_tree_handle, translated("ke_scene_tree_handle"));
    try expectSameLayout(abi.ke_script_host, translated("ke_script_host"));
    try expectSameLayout(abi.ke_script_host_handle, translated("ke_script_host_handle"));
    try expectSameLayout(abi.ke_signal_bus, translated("ke_signal_bus"));
    try expectSameLayout(abi.ke_signal_bus_handle, translated("ke_signal_bus_handle"));
    try expectSameLayout(abi.ke_component_apply_fn, c.ke_component_apply_fn);
    try expectSameLayout(abi.ke_input_action_event_func, c.ke_input_action_event_func);
    try expectSameLayout(abi.ke_script_factory_func, c.ke_script_factory_func);
    try expectSameLayout(abi.ke_script_type_id, c.ke_script_type_id);
}

test "every enum value is the header's value" {
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_TYPE_BUTTON), @as(i64, abi.KE_ACTION_TYPE_BUTTON));
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_TYPE_AXIS1D), @as(i64, abi.KE_ACTION_TYPE_AXIS1D));
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_TYPE_AXIS2D), @as(i64, abi.KE_ACTION_TYPE_AXIS2D));
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_TYPE_AXIS3D), @as(i64, abi.KE_ACTION_TYPE_AXIS3D));
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_PHASE_STARTED), @as(i64, abi.KE_ACTION_PHASE_STARTED));
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_PHASE_PERFORMED), @as(i64, abi.KE_ACTION_PHASE_PERFORMED));
    try std.testing.expectEqual(@as(i64, c.KE_ACTION_PHASE_CANCELED), @as(i64, abi.KE_ACTION_PHASE_CANCELED));
    try std.testing.expectEqual(@as(i64, c.KE_SCRIPT_REACH_SELF), @as(i64, abi.KE_SCRIPT_REACH_SELF));
    try std.testing.expectEqual(@as(i64, c.KE_SCRIPT_REACH_ANY), @as(i64, abi.KE_SCRIPT_REACH_ANY));
    try std.testing.expectEqual(@as(i64, c.KE_SCRIPT_RESOLVE_FOUND), @as(i64, abi.KE_SCRIPT_RESOLVE_FOUND));
    try std.testing.expectEqual(@as(i64, c.KE_SCRIPT_RESOLVE_NONE), @as(i64, abi.KE_SCRIPT_RESOLVE_NONE));
    try std.testing.expectEqual(@as(i64, c.KE_SCRIPT_RESOLVE_AMBIGUOUS), @as(i64, abi.KE_SCRIPT_RESOLVE_AMBIGUOUS));
    try std.testing.expectEqual(@as(i64, c.KE_SCRIPT_BORROW_DESCENDANT), @as(i64, abi.KE_SCRIPT_BORROW_DESCENDANT));
    try std.testing.expectEqual(@as(i64, c.KE_SCRIPT_BORROW_ANCESTOR), @as(i64, abi.KE_SCRIPT_BORROW_ANCESTOR));
    try std.testing.expectEqual(@as(i64, c.KE_SCRIPT_BORROW_ANYWHERE), @as(i64, abi.KE_SCRIPT_BORROW_ANYWHERE));
}
