const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_file_system_std",
        .root = "src/file_system_std.zig",
        .abi = &.{ "abi_file_system", "abi_file_system_std_factory", "abi_result" },
        .common = &.{"heap"},
        .tests = "Run the standard-library file system unit tests",
    });
}
