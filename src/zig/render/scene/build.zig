const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_scene",
        .root = "src/scene_module.zig",
        .abi = &.{ "abi_asset", "abi_ecs", "abi_framework", "abi_render", "abi_render_scene_factory", "abi_render_ui_factory", "abi_result", "abi_runtime", "abi_spatial", "abi_text" },
        .common = &.{ "heap", "stubs" },
        .tests = "Run the render scene unit tests",
    });
}
