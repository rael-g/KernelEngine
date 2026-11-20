const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_io_inline",
        .root = "src/io_inline.zig",
        .abi = &.{ "abi_part", "abi_completion", "abi_file_system", "abi_io", "abi_io_inline_factory", "abi_result", "abi_settings" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "part", .dependency = "ke_part", .module = "part" }, .{ .name = "settings_schema", .dependency = "ke_settings_schema", .module = "settings_schema" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the inline io unit tests",
    });
}
