const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_audio_module",
        .root = "src/audio_module.zig",
        .abi = &.{ "abi_audio_contract", "abi_audio_components", "abi_audio", "abi_ecs", "abi_part", "abi_result", "abi_schedule", "abi_audio_module_factory", "abi_framework", "abi_audio_node_types" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "node_catalogue", .dependency = "ke_node_catalogue", .module = "node_catalogue" }, .{ .name = "part", .dependency = "ke_part", .module = "part" }, .{ .name = "zsub", .dependency = "zsub", .module = "zsub" }},
        .tests = "Run the audio module unit tests",
    });
}
