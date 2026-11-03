const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_camera",
        .root = "src/render_camera.zig",
        .abi = &.{ "abi_view", "abi_render_contract", "abi_render_gpu", "abi_render_components", "abi_math", "abi_render", "abi_result", },
        .common = &.{"heap"},
        .tests = "Run the camera unit tests",
    });
}
