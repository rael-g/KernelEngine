const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("physics_body2d_factory.zig") });
    abi.addImport("ecs", b.dependency("abi_ecs", .{}).module("abi"));
    abi.addImport("logger", b.dependency("abi_logger", .{}).module("abi"));
    abi.addImport("module", b.dependency("abi_module", .{}).module("abi"));
    abi.addImport("physics", b.dependency("abi_physics", .{}).module("abi"));
    abi.addImport("result", b.dependency("abi_result", .{}).module("abi"));
    abi.addImport("scene_tree", b.dependency("abi_scene_tree", .{}).module("abi"));
    abi.addImport("schedule", b.dependency("abi_schedule", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/physics/body2d/body2d_module.h>
        \\#include <kernel_engine/physics/body2d/physics_body2d_log.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../../c/completion"));
    translated.addIncludePath(b.path("../../../../c/ecs"));
    translated.addIncludePath(b.path("../../../../c/framework"));
    translated.addIncludePath(b.path("../../../../c/job"));
    translated.addIncludePath(b.path("../../../../c/logger"));
    translated.addIncludePath(b.path("../../../../c/math"));
    translated.addIncludePath(b.path("../../../../c/module"));
    translated.addIncludePath(b.path("../../../../c/physics"));
    translated.addIncludePath(b.path("../../../common/include"));
    translated.addIncludePath(b.path("../include"));
    translated.addIncludePath(b.path("../../../../c/result"));
    translated.addIncludePath(b.path("../../../../c/schedule"));
    translated.addIncludePath(b.path("../../../schedule/include"));
    translated.addIncludePath(b.path("../../../../c/settings"));
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
    tests.root_module.addIncludePath(b.path("../../../../c/completion"));
    tests.root_module.addIncludePath(b.path("../../../../c/ecs"));
    tests.root_module.addIncludePath(b.path("../../../../c/framework"));
    tests.root_module.addIncludePath(b.path("../../../../c/job"));
    tests.root_module.addIncludePath(b.path("../../../../c/logger"));
    tests.root_module.addIncludePath(b.path("../../../../c/math"));
    tests.root_module.addIncludePath(b.path("../../../../c/module"));
    tests.root_module.addIncludePath(b.path("../../../../c/physics"));
    tests.root_module.addIncludePath(b.path("../../../common/include"));
    tests.root_module.addIncludePath(b.path("../include"));
    tests.root_module.addIncludePath(b.path("../../../../c/result"));
    tests.root_module.addIncludePath(b.path("../../../../c/schedule"));
    tests.root_module.addIncludePath(b.path("../../../schedule/include"));
    tests.root_module.addIncludePath(b.path("../../../../c/settings"));
    b.step("test", "Check the physics_body2d_factory ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
