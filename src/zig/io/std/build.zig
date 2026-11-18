const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_io_std",
        .root = "src/io_std.zig",
        .abi = &.{ "abi_completion", "abi_file_system", "abi_io", "abi_io_std_factory", "abi_result", "abi_settings" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "settings_schema", .dependency = "ke_settings_schema", .module = "settings_schema" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the std io unit tests",
    });
}
