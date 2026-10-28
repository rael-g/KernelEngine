const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = b.addModule("heap", .{ .root_source_file = b.path("heap.zig"), .target = target, .optimize = optimize });
    module(b, "stubs", &.{ "abi_ecs", "abi_framework", "abi_render", "abi_result", "abi_runtime" });
    module(b, "scene_components", &.{ "abi_ecs", "abi_framework", "abi_result" });
    module(b, "component_fields", &.{ "abi_ecs", "abi_math" });
}

fn module(b: *std.Build, name: []const u8, abi: []const []const u8) void {
    const mod = b.addModule(name, .{ .root_source_file = b.path(b.fmt("{s}.zig", .{name})) });
    for (abi) |a| mod.addImport(a, b.dependency(a, .{}).module("abi"));
}
