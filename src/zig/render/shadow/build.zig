const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_shadow",
        .root = "src/shadow_module.zig",
        .abi = &.{ "abi_ecs", "abi_math", "abi_render", "abi_render_shadow_factory", "abi_result", "abi_runtime", "abi_spatial", "abi_view" },
        .common = &.{"heap"},
        .render_common = &.{"object_uniforms"},
        .packages = &.{ .{ .name = "zmath", .dependency = "zmath", .module = "root" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the shadow pass unit tests",
    });
}
