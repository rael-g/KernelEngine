const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_audio_module",
        .root = "src/audio_module.zig",
        .abi = &.{ "abi_audio", "abi_ecs", "abi_framework", "abi_result" },
        .common = &.{ "scene_components", "stubs" },
        .tests = "Run the audio module unit tests",
    });
}
