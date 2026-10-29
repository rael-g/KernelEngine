const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_deferred_lighting",
        .root = "src/deferred_lighting_module.zig",
        .abi = &.{ "abi_ecs", "abi_render", "abi_render_deferred_lighting_factory", "abi_result", "abi_runtime" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "feature_bindings", .dependency = "ke_render_feature_bindings", .module = "feature_bindings" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the deferred_lighting pass unit tests",
    });
}
