const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_tonemap",
        .root = "src/tonemap_module.zig",
        .abi = &.{ "abi_render_context", "abi_framework", "abi_render_gpu", "abi_asset_resolver", "abi_ecs", "abi_render", "abi_render_tonemap_factory", "abi_result", "abi_runtime" },
        .common = &.{"heap"},
        .packages = &.{.{ .name = "zsub", .dependency = "zsub", .module = "zsub" }},
        .tests = "Run the tonemap pass unit tests",
    });
}
