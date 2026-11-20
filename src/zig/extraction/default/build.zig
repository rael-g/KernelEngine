const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_extraction_default",
        .root = "src/extraction_default.zig",
        .abi = &.{ "abi_completion", "abi_ecs", "abi_ecs_variant", "abi_extraction", "abi_extraction_default_factory", "abi_result", "abi_schedule", "abi_scheduler", "abi_part" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "part", .dependency = "ke_part", .module = "part" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the extraction unit tests",
    });
}
