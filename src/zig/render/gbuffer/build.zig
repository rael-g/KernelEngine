const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_gbuffer",
        .root = "src/gbuffer_module.zig",
        .abi = &.{ "abi_ecs", "abi_render", "abi_render_gbuffer_factory", "abi_result", "abi_runtime", "abi_spatial" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "material_pass_groups", .dependency = "ke_render_material_pass_groups", .module = "material_pass_groups" }, .{ .name = "object_uniforms", .dependency = "ke_render_object_uniforms", .module = "object_uniforms" }, .{ .name = "zmath", .dependency = "zmath", .module = "root" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" } },
        .tests = "Run the gbuffer pass unit tests",
    });
}
