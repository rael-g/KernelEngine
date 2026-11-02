const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_ui",
        .root = "src/ui_module.zig",
        .abi = &.{ "abi_render_ui", "abi_render_contract", "abi_framework", "abi_ui_components", "abi_render_handles", "abi_render_gpu", "abi_asset_resolver", "abi_ecs", "abi_render", "abi_render_ui_factory", "abi_result", "abi_runtime", "abi_text" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "zmath", .dependency = "zmath", .module = "root" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the ui pass unit tests",
    });
}
