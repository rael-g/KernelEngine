const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_tonemap",
        .root = "src/tonemap_module.zig",
        .abi = &.{ "abi_render_gpu", "abi_asset_resolver", "abi_ecs", "abi_render", "abi_render_tonemap_factory", "abi_result", "abi_schedule", "abi_part", "abi_render_frame", "abi_render_graph", "abi_extraction", "abi_completion" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "part", .dependency = "ke_part", .module = "part" }, .{ .name = "hooked_systems", .dependency = "ke_hooked_systems", .module = "hooked_systems" },.{ .name = "zsub", .dependency = "zsub", .module = "zsub" }},
        .tests = "Run the tonemap pass unit tests",
    });
}
