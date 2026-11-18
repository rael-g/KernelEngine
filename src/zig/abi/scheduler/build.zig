const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("scheduler.zig") });
    abi.addImport("async", b.dependency("abi_async", .{}).module("abi"));
    abi.addImport("completion", b.dependency("abi_completion", .{}).module("abi"));
    abi.addImport("job", b.dependency("abi_job", .{}).module("abi"));
    abi.addImport("result", b.dependency("abi_result", .{}).module("abi"));
    abi.addImport("settings", b.dependency("abi_settings", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/scheduler/scheduler.h>
        \\#include <kernel_engine/scheduler/scheduler_create.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../c/async"));
    translated.addIncludePath(b.path("../../../c/completion"));
    translated.addIncludePath(b.path("../../../c/job"));
    translated.addIncludePath(b.path("../../../c/result"));
    translated.addIncludePath(b.path("../../../c/scheduler"));
    translated.addIncludePath(b.path("../../scheduler/include"));
    translated.addIncludePath(b.path("../../common/include"));
    translated.addIncludePath(b.path("../../../c/settings"));
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
    tests.root_module.addIncludePath(b.path("../../../c/async"));
    tests.root_module.addIncludePath(b.path("../../../c/completion"));
    tests.root_module.addIncludePath(b.path("../../../c/job"));
    tests.root_module.addIncludePath(b.path("../../../c/result"));
    tests.root_module.addIncludePath(b.path("../../../c/scheduler"));
    tests.root_module.addIncludePath(b.path("../../scheduler/include"));
    tests.root_module.addIncludePath(b.path("../../common/include"));
    tests.root_module.addIncludePath(b.path("../../../c/settings"));
    b.step("test", "Check the scheduler ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
