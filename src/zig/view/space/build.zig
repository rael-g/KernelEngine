const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    ke_build.plugin(b, .{
        .name = "ke_view_space",
        .root = "src/view_space.zig",
        .abi = &.{ "abi_math", "abi_render", "abi_result", "abi_view", "abi_view_space_factory" },
        .common = &.{"heap"},
        .packages = &.{.{ .name = "zmath", .dependency = "zmath", .module = "root" }},
        .tests = "Run the view space unit tests",
    });
}
