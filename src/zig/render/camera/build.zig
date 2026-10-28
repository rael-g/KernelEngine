const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_camera",
        .root = "src/render_camera.zig",
        .abi = &.{ "abi_math", "abi_render", "abi_result", "abi_view" },
        .common = &.{"heap"},
        .tests = "Run the camera unit tests",
    });
}
