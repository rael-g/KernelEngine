const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_scheduler",
        .root = "src/scheduler.zig",
        .abi = &.{ "abi_completion", "abi_result", "abi_schedule", "abi_scheduler", "abi_scheduler_factory" },
        .common = &.{"heap"},
        .tests = "Run the scheduler unit tests",
    });
}
