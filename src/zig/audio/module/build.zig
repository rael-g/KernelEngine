const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_audio_module",
        .root = "src/audio_module.zig",
        .abi = &.{ "abi_framework", "abi_audio_contract", "abi_scene_loader", "abi_audio_components", "abi_audio", "abi_ecs", "abi_result" },
        .tests = "Run the audio module unit tests",
    });
}
