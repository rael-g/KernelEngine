const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_ui",
        .root = "src/ui_module.zig",
        .abi = &.{ "abi_render_ui", "abi_render_contract", "abi_ui_components", "abi_render_handles", "abi_render_gpu", "abi_asset_resolver", "abi_ecs", "abi_render", "abi_render_ui_factory", "abi_result", "abi_text", "abi_schedule", "abi_part", "abi_render_frame", "abi_render_graph", "abi_extraction", "abi_completion", "abi_framework", "abi_ui_node_types" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "node_catalogue", .dependency = "ke_node_catalogue", .module = "node_catalogue" }, .{ .name = "part", .dependency = "ke_part", .module = "part" }, .{ .name = "hooked_systems", .dependency = "ke_hooked_systems", .module = "hooked_systems" }, .{ .name = "zmath", .dependency = "zmath", .module = "root" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the ui pass unit tests",
    });
}
