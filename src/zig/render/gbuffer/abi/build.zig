const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("render_gbuffer_factory.zig") });
    abi.addImport("ecs", b.dependency("abi_ecs", .{}).module("abi"));
    abi.addImport("logger", b.dependency("abi_logger", .{}).module("abi"));
    abi.addImport("part", b.dependency("abi_part", .{}).module("abi"));
    abi.addImport("render", b.dependency("abi_render", .{}).module("abi"));
    abi.addImport("render_frame", b.dependency("abi_render_frame", .{}).module("abi"));
    abi.addImport("render_gpu", b.dependency("abi_render_gpu", .{}).module("abi"));
    abi.addImport("render_graph", b.dependency("abi_render_graph", .{}).module("abi"));
    abi.addImport("result", b.dependency("abi_result", .{}).module("abi"));
    abi.addImport("schedule", b.dependency("abi_schedule", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/render/gbuffer/gbuffer_create.h>
        \\#include <kernel_engine/render/gbuffer/render_gbuffer_log.h>
        \\#include <kernel_engine/render/gbuffer/render_gbuffer_parts.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../../c/tasks"));
    translated.addIncludePath(b.path("../../../../c/ecs"));
    translated.addIncludePath(b.path("../../../../c/logger"));
    translated.addIncludePath(b.path("../../../../c/math"));
    translated.addIncludePath(b.path("../../../../c/render"));
    translated.addIncludePath(b.path("../../../../c/assembly"));
    translated.addIncludePath(b.path("../include"));
    translated.addIncludePath(b.path("../../../common/include"));
    translated.addIncludePath(b.path("../../../../c/result"));
    translated.addIncludePath(b.path("../../../../c/scheduling"));
    translated.addIncludePath(b.path("../../../scheduling/schedule/include"));
    translated.addIncludePath(b.path("../../../../c/configuration"));
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
    tests.root_module.addIncludePath(b.path("../../../../c/tasks"));
    tests.root_module.addIncludePath(b.path("../../../../c/ecs"));
    tests.root_module.addIncludePath(b.path("../../../../c/logger"));
    tests.root_module.addIncludePath(b.path("../../../../c/math"));
    tests.root_module.addIncludePath(b.path("../../../../c/render"));
    tests.root_module.addIncludePath(b.path("../../../../c/assembly"));
    tests.root_module.addIncludePath(b.path("../include"));
    tests.root_module.addIncludePath(b.path("../../../common/include"));
    tests.root_module.addIncludePath(b.path("../../../../c/result"));
    tests.root_module.addIncludePath(b.path("../../../../c/scheduling"));
    tests.root_module.addIncludePath(b.path("../../../scheduling/schedule/include"));
    tests.root_module.addIncludePath(b.path("../../../../c/configuration"));
    b.step("test", "Check the render_gbuffer_factory ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
