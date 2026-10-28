const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_input_default",
        .root = "src/input_default.zig",
        .abi = &.{ "abi_input", "abi_result" },
        .common = &.{"heap"},
        .tests = "Run the default input unit tests",
    });
}
