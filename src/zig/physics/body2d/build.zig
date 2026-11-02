const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_physics_body2d",
        .root = "src/body2d_module.zig",
        .abi = &.{ "abi_math", "abi_framework_components", "abi_spatial_contract", "abi_physics_contract", "abi_framework", "abi_scene_tree", "abi_physics_components", "abi_asset_resolver", "abi_ecs", "abi_physics", "abi_physics_body2d_factory", "abi_result", "abi_runtime", "abi_spatial" },
        .common = &.{"heap"},
        .packages = &.{.{ .name = "zsub", .dependency = "zsub", .module = "zsub" }},
        .tests = "Run the body2d module unit tests",
    });
}
