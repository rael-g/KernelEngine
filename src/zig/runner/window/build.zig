const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_runner_window",
        .root = "src/runner_window.zig",
        .abi = &.{ "abi_part", "abi_result", "abi_runner", "abi_scheduler", "abi_window" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "part", .dependency = "ke_part", .module = "part" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the window runner unit tests",
    });
}
