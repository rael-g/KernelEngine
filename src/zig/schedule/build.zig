const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_schedule",
        .root = "src/schedule.zig",
        .abi = &.{ "abi_ecs", "abi_result", "abi_schedule", "abi_schedule_factory", "abi_job", "abi_completion", "abi_settings" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "settings_schema", .dependency = "ke_settings_schema", .module = "settings_schema" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" }},
        .tests = "Run the schedule unit tests",
    });
}
