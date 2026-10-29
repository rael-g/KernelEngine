const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("material_pass_groups", .{ .root_source_file = b.path("material_pass_groups.zig"), .target = target, .optimize = optimize });
    mod.addImport("abi_render", b.dependency("abi_render", .{}).module("abi"));
    mod.addImport("abi_result", b.dependency("abi_result", .{}).module("abi"));
}
