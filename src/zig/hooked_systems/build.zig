const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("hooked_systems", .{ .root_source_file = b.path("hooked_systems.zig"), .target = target, .optimize = optimize });
    mod.addImport("abi_ecs", b.dependency("abi_ecs", .{}).module("abi"));
    mod.addImport("abi_schedule", b.dependency("abi_schedule", .{}).module("abi"));
    mod.addImport("abi_result", b.dependency("abi_result", .{}).module("abi"));
}
