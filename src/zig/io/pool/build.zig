const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_io_pool",
        .root = "src/io_pool.zig",
        .abi = &.{ "abi_file_system", "abi_io", "abi_io_pool_factory", "abi_result", "abi_task_pool" },
        .common = &.{"heap"},
        .packages = &.{.{ .name = "zsub", .dependency = "zsub", .module = "zsub" }},
        .tests = "Run the pooled io unit tests",
    });
}
