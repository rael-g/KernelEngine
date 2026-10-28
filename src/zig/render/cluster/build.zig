const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_cluster",
        .root = "src/cluster_module.zig",
        .abi = &.{ "abi_ecs", "abi_render", "abi_render_cluster_factory", "abi_result", "abi_runtime", "abi_spatial", "abi_view" },
        .common = &.{"heap"},
        .stubs = &.{ "render", "runtime" },
        .render_common = &.{"feature_bindings"},
        .tests = "Run the cluster pass unit tests",
    });
}
