const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_scheduler",
        .root = "src/scheduler.zig",
        .abi = &.{ "abi_async", "abi_completion", "abi_job", "abi_result", "abi_scheduler", "abi_scheduler_factory", "abi_settings", "abi_part" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "settings_schema", .dependency = "ke_settings_schema", .module = "settings_schema" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" }},
        .tests = "Run the scheduler unit tests",
    });
}
