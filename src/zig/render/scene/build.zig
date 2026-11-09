const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_scene",
        .root = "src/scene_module.zig",
        .abi = &.{ "abi_render_context", "abi_render_ui", "abi_spatial_contract", "abi_render_contract", "abi_framework", "abi_ui_components", "abi_render_handles", "abi_mesh", "abi_math", "abi_render_components", "abi_ecs_variant", "abi_asset_resolver", "abi_ecs", "abi_render", "abi_render_scene_factory", "abi_render_ui_factory", "abi_result", "abi_runtime", "abi_spatial", "abi_text" },
        .common = &.{"heap"},
        .packages = &.{.{ .name = "zsub", .dependency = "zsub", .module = "zsub" }},
        .tests = "Run the render scene unit tests",
    });
}
