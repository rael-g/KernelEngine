const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_view_space",
        .root = "src/view_space.zig",
        .abi = &.{ "abi_view", "abi_render_gpu", "abi_math", "abi_render", "abi_result", },
        .common = &.{"heap"},
        .packages = &.{.{ .name = "zmath", .dependency = "zmath", .module = "root" }},
        .tests = "Run the view space unit tests",
    });
}
