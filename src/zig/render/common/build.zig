const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    module(b, target, optimize, "feature_bindings", &.{"abi_render"});
    module(b, target, optimize, "material_pass_groups", &.{ "abi_render", "abi_result" });
    module(b, target, optimize, "object_uniforms", &.{ "abi_render", "abi_result" });
}

fn module(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, name: []const u8, abi: []const []const u8) void {
    const mod = b.addModule(name, .{ .root_source_file = b.path(b.fmt("{s}.zig", .{name})), .target = target, .optimize = optimize });
    for (abi) |a| mod.addImport(a, b.dependency(a, .{}).module("abi"));
}
