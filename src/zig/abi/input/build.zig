const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("input.zig") });
    abi.addImport("math", b.dependency("abi_math", .{}).module("abi"));
    abi.addImport("result", b.dependency("abi_result", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/input/input.h>
        \\#include <kernel_engine/input/snapshot.h>
        \\#include <kernel_engine/input/event.h>
        \\#include <kernel_engine/input/key.h>
        \\#include <kernel_engine/input/default/input_default_create.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../c/input"));
    translated.addIncludePath(b.path("../../../c/math"));
    translated.addIncludePath(b.path("../../input/default/include"));
    translated.addIncludePath(b.path("../../common/include"));
    translated.addIncludePath(b.path("../../../c/result"));
    translated.addIncludePath(b.path("../../../c/ecs"));
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
    tests.root_module.addIncludePath(b.path("../../../c/input"));
    tests.root_module.addIncludePath(b.path("../../../c/math"));
    tests.root_module.addIncludePath(b.path("../../input/default/include"));
    tests.root_module.addIncludePath(b.path("../../common/include"));
    tests.root_module.addIncludePath(b.path("../../../c/result"));
    tests.root_module.addIncludePath(b.path("../../../c/ecs"));
    b.step("test", "Check the input ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
