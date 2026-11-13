const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("gpu_device_webgpu_factory.zig") });
    abi.addImport("completion", b.dependency("abi_completion", .{}).module("abi"));
    abi.addImport("logger", b.dependency("abi_logger", .{}).module("abi"));
    abi.addImport("render_gpu", b.dependency("abi_render_gpu", .{}).module("abi"));
    abi.addImport("result", b.dependency("abi_result", .{}).module("abi"));
    abi.addImport("task_pool", b.dependency("abi_task_pool", .{}).module("abi"));
    abi.addImport("window", b.dependency("abi_window", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
        \\#include <kernel_engine/render/webgpu/gpu_device_webgpu_log.h>
        \\#include <kernel_engine/render/webgpu/gpu_render_target_webgpu_window_create.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../../c/completion"));
    translated.addIncludePath(b.path("../include"));
    translated.addIncludePath(b.path("../../../common/include"));
    translated.addIncludePath(b.path("../../../../c/logger"));
    translated.addIncludePath(b.path("../../../../c/render"));
    translated.addIncludePath(b.path("../../../../c/result"));
    translated.addIncludePath(b.path("../../../../c/task_pool"));
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
    tests.root_module.addIncludePath(b.path("../../../../c/completion"));
    tests.root_module.addIncludePath(b.path("../include"));
    tests.root_module.addIncludePath(b.path("../../../common/include"));
    tests.root_module.addIncludePath(b.path("../../../../c/logger"));
    tests.root_module.addIncludePath(b.path("../../../../c/render"));
    tests.root_module.addIncludePath(b.path("../../../../c/result"));
    tests.root_module.addIncludePath(b.path("../../../../c/task_pool"));
    tests.root_module.addIncludePath(b.path("../../../../c/window"));
    b.step("test", "Check the gpu_device_webgpu_factory ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
