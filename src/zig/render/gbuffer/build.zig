const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_gbuffer",
        .root = "src/gbuffer_module.zig",
        .abi = &.{ "abi_ecs", "abi_render", "abi_render_gbuffer_factory", "abi_result", "abi_runtime", "abi_spatial" },
        .common = &.{"heap"},
        .render_common = &.{ "material_pass_groups", "object_uniforms" },
        .packages = &.{ .{ .name = "zmath", .dependency = "zmath", .module = "root" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the gbuffer pass unit tests",
    });
}
