const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_configuration",
        .root = "src/configuration.zig",
        .abi = &.{ "abi_configuration", "abi_result" },
        .common = &.{"heap"},
        .tests = "Run unit tests",
    });
}
