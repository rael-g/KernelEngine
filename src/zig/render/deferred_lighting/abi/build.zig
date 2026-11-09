const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("render_deferred_lighting_factory.zig") });
    abi.addImport("ecs", b.dependency("abi_ecs", .{}).module("abi"));
    abi.addImport("logger", b.dependency("abi_logger", .{}).module("abi"));
    abi.addImport("render", b.dependency("abi_render", .{}).module("abi"));
    abi.addImport("render_context", b.dependency("abi_render_context", .{}).module("abi"));
    abi.addImport("render_gpu", b.dependency("abi_render_gpu", .{}).module("abi"));
    abi.addImport("result", b.dependency("abi_result", .{}).module("abi"));
    abi.addImport("runtime", b.dependency("abi_runtime", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/render/deferred_lighting/deferred_lighting_create.h>
        \\#include <kernel_engine/render/deferred_lighting/render_deferred_lighting_log.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../../c/ecs"));
    translated.addIncludePath(b.path("../../../../c/math"));
    translated.addIncludePath(b.path("../../../common/include"));
    translated.addIncludePath(b.path("../../../../c/result"));
    translated.addIncludePath(b.path("../../../../c/logger"));
    translated.addIncludePath(b.path("../../../../c/render"));
    translated.addIncludePath(b.path("../../../../c/spatial"));
    translated.addIncludePath(b.path("../../../../c/view"));
    translated.addIncludePath(b.path("../../../../c/asset"));
    translated.addIncludePath(b.path("../../../../c/audio"));
    translated.addIncludePath(b.path("../../../../c/configuration"));
    translated.addIncludePath(b.path("../../../../c/file_system"));
    translated.addIncludePath(b.path("../../../../c/framework"));
    translated.addIncludePath(b.path("../../../../c/input"));
    translated.addIncludePath(b.path("../../../../c/io"));
    translated.addIncludePath(b.path("../../../../c/physics"));
    translated.addIncludePath(b.path("../../../../c/resource_cache"));
    translated.addIncludePath(b.path("../../../../c/runtime"));
    translated.addIncludePath(b.path("../../../../c/task_pool"));
    translated.addIncludePath(b.path("../../../../c/text"));
    translated.addIncludePath(b.path("../../../../c/window"));
    translated.addIncludePath(b.path("../include"));
    translated.addIncludePath(b.path("../../../runtime/include"));
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
    tests.root_module.addIncludePath(b.path("../../../../c/ecs"));
    tests.root_module.addIncludePath(b.path("../../../../c/math"));
    tests.root_module.addIncludePath(b.path("../../../common/include"));
    tests.root_module.addIncludePath(b.path("../../../../c/result"));
    tests.root_module.addIncludePath(b.path("../../../../c/logger"));
    tests.root_module.addIncludePath(b.path("../../../../c/render"));
    tests.root_module.addIncludePath(b.path("../../../../c/spatial"));
    tests.root_module.addIncludePath(b.path("../../../../c/view"));
    tests.root_module.addIncludePath(b.path("../../../../c/asset"));
    tests.root_module.addIncludePath(b.path("../../../../c/audio"));
    tests.root_module.addIncludePath(b.path("../../../../c/configuration"));
    tests.root_module.addIncludePath(b.path("../../../../c/file_system"));
    tests.root_module.addIncludePath(b.path("../../../../c/framework"));
    tests.root_module.addIncludePath(b.path("../../../../c/input"));
    tests.root_module.addIncludePath(b.path("../../../../c/io"));
    tests.root_module.addIncludePath(b.path("../../../../c/physics"));
    tests.root_module.addIncludePath(b.path("../../../../c/resource_cache"));
    tests.root_module.addIncludePath(b.path("../../../../c/runtime"));
    tests.root_module.addIncludePath(b.path("../../../../c/task_pool"));
    tests.root_module.addIncludePath(b.path("../../../../c/text"));
    tests.root_module.addIncludePath(b.path("../../../../c/window"));
    tests.root_module.addIncludePath(b.path("../include"));
    tests.root_module.addIncludePath(b.path("../../../runtime/include"));
    b.step("test", "Check the render_deferred_lighting_factory ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
