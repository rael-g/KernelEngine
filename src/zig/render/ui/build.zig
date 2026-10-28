const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_ui",
        .root = "src/ui_module.zig",
        .abi = &.{ "abi_ecs", "abi_render", "abi_render_ui_factory", "abi_result", "abi_runtime", "abi_text" },
        .common = &.{"heap"},
        .stubs = &.{ "ecs", "render", "runtime" },
        .render_common = &.{"handle"},
        .packages = &.{.{ .name = "zmath", .dependency = "zmath", .module = "root" }},
        .tests = "Run the ui pass unit tests",
    });
}
