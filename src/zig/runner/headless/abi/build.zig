const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("runner_headless_factory.zig") });
    abi.addImport("completion", b.dependency("abi_completion", .{}).module("abi"));
    abi.addImport("input", b.dependency("abi_input", .{}).module("abi"));
    abi.addImport("logger", b.dependency("abi_logger", .{}).module("abi"));
    abi.addImport("part", b.dependency("abi_part", .{}).module("abi"));
    abi.addImport("result", b.dependency("abi_result", .{}).module("abi"));
    abi.addImport("runner", b.dependency("abi_runner", .{}).module("abi"));
    abi.addImport("scheduler", b.dependency("abi_scheduler", .{}).module("abi"));
    abi.addImport("settings", b.dependency("abi_settings", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/runner/headless/runner_headless_create.h>
        \\#include <kernel_engine/runner/headless/runner_headless_log.h>
        \\#include <kernel_engine/runner/headless/runner_headless_parts.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../../c/tasks"));
    translated.addIncludePath(b.path("../../../../c/input"));
    translated.addIncludePath(b.path("../../../input/default/include"));
    translated.addIncludePath(b.path("../../../common/include"));
    translated.addIncludePath(b.path("../../../../c/logger"));
    translated.addIncludePath(b.path("../../../../c/math"));
    translated.addIncludePath(b.path("../../../../c/assembly"));
    translated.addIncludePath(b.path("../../../../c/result"));
    translated.addIncludePath(b.path("../../../../c/runner"));
    translated.addIncludePath(b.path("../include"));
    translated.addIncludePath(b.path("../../../../c/scheduler"));
    translated.addIncludePath(b.path("../../../scheduler/include"));
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
    tests.root_module.addIncludePath(b.path("../../../../c/input"));
    tests.root_module.addIncludePath(b.path("../../../input/default/include"));
    tests.root_module.addIncludePath(b.path("../../../common/include"));
    tests.root_module.addIncludePath(b.path("../../../../c/logger"));
    tests.root_module.addIncludePath(b.path("../../../../c/math"));
    tests.root_module.addIncludePath(b.path("../../../../c/assembly"));
    tests.root_module.addIncludePath(b.path("../../../../c/result"));
    tests.root_module.addIncludePath(b.path("../../../../c/runner"));
    tests.root_module.addIncludePath(b.path("../include"));
    tests.root_module.addIncludePath(b.path("../../../../c/scheduler"));
    tests.root_module.addIncludePath(b.path("../../../scheduler/include"));
    tests.root_module.addIncludePath(b.path("../../../../c/configuration"));
    b.step("test", "Check the runner_headless_factory ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
