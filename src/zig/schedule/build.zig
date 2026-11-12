const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_schedule",
        .root = "src/schedule.zig",
        .abi = &.{ "abi_ecs", "abi_result", "abi_schedule", "abi_schedule_factory", "abi_task_pool" },
        .common = &.{"heap"},
        .packages = &.{.{ .name = "zsub", .dependency = "zsub", .module = "zsub" }},
        .tests = "Run the schedule unit tests",
    });
}
