const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_io_async",
        .root = "src/io_async.zig",
        .abi = &.{ "abi_async", "abi_completion", "abi_file_system", "abi_io", "abi_io_async_factory", "abi_result" },
        .common = &.{"heap"},
        .packages = &.{.{ .name = "zsub", .dependency = "zsub", .module = "zsub" }},
        .tests = "Run the async io unit tests",
    });
}
