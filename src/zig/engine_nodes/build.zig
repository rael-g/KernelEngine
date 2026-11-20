const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_engine_nodes",
        .root = "src/engine_nodes.zig",
        .abi = &.{ "abi_engine_node_types", "abi_engine_nodes_factory", "abi_framework", "abi_part", "abi_result" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "part", .dependency = "ke_part", .module = "part" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the engine nodes unit tests",
    });
}
