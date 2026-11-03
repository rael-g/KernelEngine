const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_shadow",
        .root = "src/shadow_module.zig",
        .abi = &.{ "abi_view", "abi_render_contract", "abi_framework", "abi_render_gpu", "abi_render_components", "abi_asset_resolver", "abi_ecs", "abi_math", "abi_render", "abi_render_shadow_factory", "abi_result", "abi_runtime", "abi_spatial", },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "object_uniforms", .dependency = "ke_render_object_uniforms", .module = "object_uniforms" }, .{ .name = "zmath", .dependency = "zmath", .module = "root" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the shadow pass unit tests",
    });
}
