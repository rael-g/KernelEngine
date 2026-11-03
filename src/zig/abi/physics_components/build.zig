const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("physics_components.zig") });
    abi.addImport("math", b.dependency("abi_math", .{}).module("abi"));
    abi.addImport("physics", b.dependency("abi_physics", .{}).module("abi"));
    abi.addImport("result", b.dependency("abi_result", .{}).module("abi"));
    abi.addImport("spatial", b.dependency("abi_spatial", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/physics/components.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../c/math"));
    translated.addIncludePath(b.path("../../common/include"));
    translated.addIncludePath(b.path("../../../c/result"));
    translated.addIncludePath(b.path("../../../c/physics"));
    translated.addIncludePath(b.path("../../../c/spatial"));
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("layout_test.zig"),
        .link_libc = true,
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "abi", .module = abi },
            .{ .name = "c", .module = translated.createModule() },
        },
    }) });
    tests.root_module.addCSourceFile(.{ .file = b.path("layout_values.c") });
    tests.root_module.addIncludePath(b.path("../../../c/math"));
    tests.root_module.addIncludePath(b.path("../../common/include"));
    tests.root_module.addIncludePath(b.path("../../../c/result"));
    tests.root_module.addIncludePath(b.path("../../../c/physics"));
    tests.root_module.addIncludePath(b.path("../../../c/spatial"));
    b.step("test", "Check the physics_components ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
