const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_runner_headless",
        .root = "src/runner_headless.zig",
        .abi = &.{ "abi_input", "abi_part", "abi_result", "abi_runner", "abi_scheduler", "abi_settings" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "input_names", .dependency = "ke_input_names", .module = "input_names" }, .{ .name = "part", .dependency = "ke_part", .module = "part" }, .{ .name = "settings_schema", .dependency = "ke_settings_schema", .module = "settings_schema" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the headless runner unit tests",
    });
}
