const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_deferred_lighting",
        .root = "src/deferred_lighting_module.zig",
        .abi = &.{ "abi_render_handles", "abi_render_gpu", "abi_render_components", "abi_asset_resolver", "abi_ecs", "abi_render", "abi_render_deferred_lighting_factory", "abi_result", "abi_schedule", "abi_part", "abi_render_frame", "abi_render_graph", "abi_extraction", "abi_completion", "abi_settings" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "part", .dependency = "ke_part", .module = "part" }, .{ .name = "settings_schema", .dependency = "ke_settings_schema", .module = "settings_schema" },  .{ .name = "hooked_systems", .dependency = "ke_hooked_systems", .module = "hooked_systems" }, .{ .name = "feature_bindings", .dependency = "ke_render_feature_bindings", .module = "feature_bindings" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the deferred_lighting pass unit tests",
    });
}
