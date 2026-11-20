const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("completion_graph", .{ .root_source_file = b.path("completion_graph.zig"), .target = target, .optimize = optimize });
    mod.addImport("abi_completion", b.dependency("abi_completion", .{}).module("abi"));
    mod.addImport("abi_result", b.dependency("abi_result", .{}).module("abi"));
}
