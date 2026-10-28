const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_gpu_render_target_texture",
        .root = "src/texture_target.zig",
        .abi = &.{ "abi_gpu_render_target_texture_factory", "abi_render", "abi_result" },
        .common = &.{"heap"},
        .tests = "Run the texture render target unit tests",
    });
}
