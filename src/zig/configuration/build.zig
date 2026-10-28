const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    ke_build.plugin(b, .{
        .name = "ke_configuration",
        .root = "src/configuration.zig",
        .abi = &.{ "abi_configuration", "abi_configuration_factory", "abi_result" },
        .common = &.{"heap"},
        .tests = "Run unit tests",
    });
}
