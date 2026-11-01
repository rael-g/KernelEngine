const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_cluster",
        .root = "src/cluster_module.zig",
        .abi = &.{ "abi_configuration", "abi_view", "abi_render_contract", "abi_framework", "abi_render_gpu", "abi_render_components", "abi_asset_resolver", "abi_ecs", "abi_render", "abi_render_cluster_factory", "abi_result", "abi_runtime", "abi_spatial", },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "feature_bindings", .dependency = "ke_render_feature_bindings", .module = "feature_bindings" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the cluster pass unit tests",
    });
}
