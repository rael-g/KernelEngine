const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_camera",
        .root = "src/render_camera.zig",
        .abi = &.{ "abi_part", "abi_view", "abi_render_contract", "abi_render_gpu", "abi_render_components", "abi_math", "abi_render", "abi_result", },
        .packages = &.{.{ .name = "part", .dependency = "ke_part", .module = "part" }},
        .common = &.{"heap"},
        .tests = "Run the camera unit tests",
    });
}
