const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_async_inline",
        .root = "src/async_inline.zig",
        .abi = &.{ "abi_part", "abi_completion", "abi_async", "abi_async_inline_factory", "abi_result", "abi_settings" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "part", .dependency = "ke_part", .module = "part" }, .{ .name = "settings_schema", .dependency = "ke_settings_schema", .module = "settings_schema" },  .{ .name = "completion_graph", .dependency = "ke_completion_graph", .module = "completion_graph" }, .{ .name = "async_suite", .dependency = "ke_async_suite", .module = "async_suite" } },
        .tests = "Run the inline async system unit tests",
    });
}
