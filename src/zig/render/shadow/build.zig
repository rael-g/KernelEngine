const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_shadow",
        .root = "src/shadow_module.zig",
        .abi = &.{ "abi_view", "abi_render_gpu", "abi_render_components", "abi_asset_resolver", "abi_ecs", "abi_math", "abi_render", "abi_render_shadow_factory", "abi_result", "abi_spatial", "abi_schedule", "abi_part", "abi_render_frame", "abi_render_graph", "abi_extraction", "abi_completion", "abi_settings" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "settings_schema", .dependency = "ke_settings_schema", .module = "settings_schema" }, .{ .name = "hooked_systems", .dependency = "ke_hooked_systems", .module = "hooked_systems" }, .{ .name = "object_uniforms", .dependency = "ke_render_object_uniforms", .module = "object_uniforms" }, .{ .name = "zmath", .dependency = "zmath", .module = "root" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the shadow pass unit tests",
    });
}
