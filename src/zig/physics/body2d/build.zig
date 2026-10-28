const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_physics_body2d",
        .root = "src/body2d_module.zig",
        .abi = &.{ "abi_ecs", "abi_framework", "abi_physics", "abi_physics_body2d_factory", "abi_result", "abi_runtime", "abi_spatial" },
        .common = &.{ "heap", "scene_components", "stubs" },
        .tests = "Run the body2d module unit tests",
    });
}
