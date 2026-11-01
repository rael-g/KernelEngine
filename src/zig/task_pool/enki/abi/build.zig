const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("task_pool_enki_factory.zig") });
    abi.addImport("logger", b.dependency("abi_logger", .{}).module("abi"));
    abi.addImport("result", b.dependency("abi_result", .{}).module("abi"));
    abi.addImport("task_pool", b.dependency("abi_task_pool", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/task_pool/enki/enki_task_pool.h>
        \\#include <kernel_engine/task_pool/enki/task_pool_enki_log.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../../c/logger"));
    translated.addIncludePath(b.path("../../../../c/math"));
    translated.addIncludePath(b.path("../../../common/include"));
    translated.addIncludePath(b.path("../../../../c/result"));
    translated.addIncludePath(b.path("../../../../c/task_pool"));
    translated.addIncludePath(b.path("../include"));
    translated.addIncludePath(b.path("../../../../c/asset"));
    translated.addIncludePath(b.path("../../../../c/audio"));
    translated.addIncludePath(b.path("../../../../c/configuration"));
    translated.addIncludePath(b.path("../../../../c/ecs"));
    translated.addIncludePath(b.path("../../../../c/file_system"));
    translated.addIncludePath(b.path("../../../../c/framework"));
    translated.addIncludePath(b.path("../../../../c/input"));
    translated.addIncludePath(b.path("../../../../c/io"));
    translated.addIncludePath(b.path("../../../../c/physics"));
    translated.addIncludePath(b.path("../../../../c/render"));
    translated.addIncludePath(b.path("../../../../c/resource_cache"));
    translated.addIncludePath(b.path("../../../../c/runtime"));
    translated.addIncludePath(b.path("../../../../c/spatial"));
    translated.addIncludePath(b.path("../../../../c/text"));
    translated.addIncludePath(b.path("../../../../c/view"));
    translated.addIncludePath(b.path("../../../../c/window"));
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
    tests.root_module.addIncludePath(b.path("../../../../c/logger"));
    tests.root_module.addIncludePath(b.path("../../../../c/math"));
    tests.root_module.addIncludePath(b.path("../../../common/include"));
    tests.root_module.addIncludePath(b.path("../../../../c/result"));
    tests.root_module.addIncludePath(b.path("../../../../c/task_pool"));
    tests.root_module.addIncludePath(b.path("../include"));
    tests.root_module.addIncludePath(b.path("../../../../c/asset"));
    tests.root_module.addIncludePath(b.path("../../../../c/audio"));
    tests.root_module.addIncludePath(b.path("../../../../c/configuration"));
    tests.root_module.addIncludePath(b.path("../../../../c/ecs"));
    tests.root_module.addIncludePath(b.path("../../../../c/file_system"));
    tests.root_module.addIncludePath(b.path("../../../../c/framework"));
    tests.root_module.addIncludePath(b.path("../../../../c/input"));
    tests.root_module.addIncludePath(b.path("../../../../c/io"));
    tests.root_module.addIncludePath(b.path("../../../../c/physics"));
    tests.root_module.addIncludePath(b.path("../../../../c/render"));
    tests.root_module.addIncludePath(b.path("../../../../c/resource_cache"));
    tests.root_module.addIncludePath(b.path("../../../../c/runtime"));
    tests.root_module.addIncludePath(b.path("../../../../c/spatial"));
    tests.root_module.addIncludePath(b.path("../../../../c/text"));
    tests.root_module.addIncludePath(b.path("../../../../c/view"));
    tests.root_module.addIncludePath(b.path("../../../../c/window"));
    b.step("test", "Check the task_pool_enki_factory ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
