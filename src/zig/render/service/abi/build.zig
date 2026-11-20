const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("render_service_factory.zig") });
    abi.addImport("io", b.dependency("abi_io", .{}).module("abi"));
    abi.addImport("logger", b.dependency("abi_logger", .{}).module("abi"));
    abi.addImport("math", b.dependency("abi_math", .{}).module("abi"));
    abi.addImport("part", b.dependency("abi_part", .{}).module("abi"));
    abi.addImport("render", b.dependency("abi_render", .{}).module("abi"));
    abi.addImport("render_gpu", b.dependency("abi_render_gpu", .{}).module("abi"));
    abi.addImport("result", b.dependency("abi_result", .{}).module("abi"));
    abi.addImport("settings", b.dependency("abi_settings", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/render/service/render_service_create.h>
        \\#include <kernel_engine/render/service/render_service_log.h>
        \\#include <kernel_engine/render/service/render_service_parts.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../../c/completion"));
    translated.addIncludePath(b.path("../../../../c/ecs"));
    translated.addIncludePath(b.path("../../../../c/file_system"));
    translated.addIncludePath(b.path("../../../../c/io"));
    translated.addIncludePath(b.path("../../../../c/logger"));
    translated.addIncludePath(b.path("../../../../c/math"));
    translated.addIncludePath(b.path("../../../../c/render"));
    translated.addIncludePath(b.path("../../../../c/part"));
    translated.addIncludePath(b.path("../include"));
    translated.addIncludePath(b.path("../../../common/include"));
    translated.addIncludePath(b.path("../../../../c/result"));
    translated.addIncludePath(b.path("../../../../c/settings"));
    translated.addIncludePath(b.path("../../../../c/spatial"));
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
    tests.root_module.addIncludePath(b.path("../../../../c/file_system"));
    tests.root_module.addIncludePath(b.path("../../../../c/io"));
    tests.root_module.addIncludePath(b.path("../../../../c/logger"));
    tests.root_module.addIncludePath(b.path("../../../../c/math"));
    tests.root_module.addIncludePath(b.path("../../../../c/render"));
    tests.root_module.addIncludePath(b.path("../../../../c/part"));
    tests.root_module.addIncludePath(b.path("../include"));
    tests.root_module.addIncludePath(b.path("../../../common/include"));
    tests.root_module.addIncludePath(b.path("../../../../c/result"));
    tests.root_module.addIncludePath(b.path("../../../../c/settings"));
    tests.root_module.addIncludePath(b.path("../../../../c/spatial"));
    b.step("test", "Check the render_service_factory ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
