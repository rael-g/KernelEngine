const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_graph_simple",
        .root = "src/render_graph_simple.zig",
        .abi = &.{ "abi_part", "abi_completion", "abi_render_gpu", "abi_render_graph", "abi_render_graph_simple_factory", "abi_result" },
        .packages = &.{.{ .name = "part", .dependency = "ke_part", .module = "part" }},
        .common = &.{"heap"},
        .tests = "Run the render graph unit tests",
    });
}
