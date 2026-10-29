const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    module(b, "feature_bindings", &.{"abi_render"});
    module(b, "material_pass_groups", &.{ "abi_render", "abi_result" });
    module(b, "object_uniforms", &.{ "abi_render", "abi_result" });
    const shader_files = b.addModule("shader_files", .{ .root_source_file = b.path("shader_files.zig"), .target = target, .optimize = optimize, .link_libc = true });
    shader_files.addImport("c", ke_build.cImports(b, shader_files, b.path("stdio.h")));
}

fn module(b: *std.Build, name: []const u8, abi: []const []const u8) void {
    const mod = b.addModule(name, .{ .root_source_file = b.path(b.fmt("{s}.zig", .{name})) });
    for (abi) |a| mod.addImport(a, b.dependency(a, .{}).module("abi"));
}
