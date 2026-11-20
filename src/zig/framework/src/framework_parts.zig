//! The framework library's parts, gathered from the file of each factory.

const std = @import("std");
const abi_part = @import("abi_part");

const parts = blk: {
    var all = @import("scene_tree.zig").parts ++ @import("asset_resolver.zig").parts ++ @import("input_actions.zig").parts ++
        @import("scene_hierarchy.zig").parts ++ @import("node_types.zig").parts ++ @import("scene_files.zig").parts;
    const log: @FieldType(abi_part.c.ke_part, "set_log") = @ptrCast(&@import("log").Destination("ke_framework").setLogCallback);
    for (&all) |*p| p.set_log = log;
    const final = all;
    break :blk final;
};

/// The library's parts.
export fn ke_framework_parts(out_count: ?*usize) callconv(.c) ?*const abi_part.c.ke_part {
    if (out_count) |n| n.* = parts.len;
    return &parts[0];
}

test "the library's parts are the framework's, each with the library's log" {
    var count: usize = 0;
    const all: [*]const abi_part.c.ke_part = @ptrCast(ke_framework_parts(&count).?);
    try std.testing.expectEqual(@as(usize, 8), count);
    const names = [_][]const u8{ "scene_tree", "asset_resolver", "input_actions", "input_actions_evaluation", "scene_hierarchy", "node_types", "node_types_systems", "scene_files" };
    for (names, all[0..count]) |name, p| {
        try std.testing.expectEqualStrings(name, std.mem.span(p.name.?));
        try std.testing.expect(p.set_log != null);
    }
}
