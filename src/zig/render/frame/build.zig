const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_frame",
        .root = "src/frame_module.zig",
        .abi = &.{ "abi_render_contract", "abi_render_components", "abi_render_frame", "abi_render_graph", "abi_render_gpu", "abi_completion", "abi_part", "abi_schedule", "abi_ecs", "abi_math", "abi_render", "abi_render_frame_factory", "abi_result", "abi_spatial", "abi_settings" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "hooked_systems", .dependency = "ke_hooked_systems", .module = "hooked_systems" }, .{ .name = "settings_schema", .dependency = "ke_settings_schema", .module = "settings_schema" }, .{ .name = "zmath", .dependency = "zmath", .module = "root" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the render frame unit tests",
    });
}
