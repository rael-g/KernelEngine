const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_skybox",
        .root = "src/skybox_module.zig",
        .abi = &.{ "abi_render_contract", "abi_render_handles", "abi_render_gpu", "abi_render_components", "abi_asset_resolver", "abi_ecs", "abi_math", "abi_render", "abi_render_skybox_factory", "abi_result", "abi_spatial", "abi_schedule", "abi_part", "abi_render_frame", "abi_render_graph", "abi_extraction", "abi_completion" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "part", .dependency = "ke_part", .module = "part" }, .{ .name = "hooked_systems", .dependency = "ke_hooked_systems", .module = "hooked_systems" }, .{ .name = "zmath", .dependency = "zmath", .module = "root" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the skybox pass unit tests",
    });
}
