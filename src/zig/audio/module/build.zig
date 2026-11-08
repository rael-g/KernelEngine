const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_audio_module",
        .root = "src/audio_module.zig",
        .abi = &.{ "abi_audio_contract", "abi_audio_components", "abi_audio", "abi_ecs", "abi_result", "abi_runtime", "abi_audio_module_factory" },
        .common = &.{"heap"},
        .packages = &.{.{ .name = "zsub", .dependency = "zsub", .module = "zsub" }},
        .tests = "Run the audio module unit tests",
    });
}
