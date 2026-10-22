const std = @import("std");
const ke_build = @import("ke_build");

/// The `result` module, for a plugin build that imports this file as `ke_result`.
pub fn result(b: *std.Build) *std.Build.Module {
    return b.dependencyFromBuildZig(@This(), .{}).module("result");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("result", .{ .root_source_file = b.path("result.zig") });

    const test_mod = b.createModule(.{
        .root_source_file = b.path("result.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addIncludePath(b.path("../../c/result"));
    test_mod.addImport("c", ke_build.cImports(b, test_mod, b.path("test/c.h")));
    const tests = b.addTest(.{ .root_module = test_mod });
    b.step("test", "Run the result conversion tests").dependOn(&b.addRunArtifact(tests).step);
}
