const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("gpu_device_webgpu_factory.zig") });
    abi.addImport("logger", b.dependency("ke_abi_logger", .{}).module("abi"));
    abi.addImport("render", b.dependency("ke_abi_render", .{}).module("abi"));
    abi.addImport("result", b.dependency("ke_abi_result", .{}).module("abi"));
    abi.addImport("task_pool", b.dependency("ke_abi_task_pool", .{}).module("abi"));
    abi.addImport("window", b.dependency("ke_abi_window", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
        \\#include <kernel_engine/render/webgpu/gpu_device_webgpu_log.h>
        \\#include <kernel_engine/render/webgpu/gpu_render_target_webgpu_window_create.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../../c/ecs"));
    translated.addIncludePath(b.path("../include"));
    translated.addIncludePath(b.path("../../../../c/logger"));
    translated.addIncludePath(b.path("../../../../c/math"));
    translated.addIncludePath(b.path("../../../../c/render"));
    translated.addIncludePath(b.path("../../../../c/result"));
    translated.addIncludePath(b.path("../../../../c/spatial"));
    translated.addIncludePath(b.path("../../../../c/task_pool"));
    translated.addIncludePath(b.path("../../../../c/window"));
    translated.addIncludePath(b.path("../../../common/include"));
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("layout_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "abi", .module = abi },
            .{ .name = "c", .module = translated.createModule() },
        },
    }) });
    b.step("test", "Check the gpu_device_webgpu_factory ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
