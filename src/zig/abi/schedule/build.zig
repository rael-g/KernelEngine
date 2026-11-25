const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("schedule.zig") });
    abi.addImport("completion", b.dependency("abi_completion", .{}).module("abi"));
    abi.addImport("ecs", b.dependency("abi_ecs", .{}).module("abi"));
    abi.addImport("job", b.dependency("abi_job", .{}).module("abi"));
    abi.addImport("result", b.dependency("abi_result", .{}).module("abi"));
    abi.addImport("settings", b.dependency("abi_settings", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/scheduling/schedule.h>
        \\#include <kernel_engine/schedule/schedule_create.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../c/tasks"));
    translated.addIncludePath(b.path("../../../c/ecs"));
    translated.addIncludePath(b.path("../../../c/math"));
    translated.addIncludePath(b.path("../../../c/result"));
    translated.addIncludePath(b.path("../../../c/scheduling"));
    translated.addIncludePath(b.path("../../scheduling/schedule/include"));
    translated.addIncludePath(b.path("../../common/include"));
    translated.addIncludePath(b.path("../../../c/configuration"));
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
    tests.root_module.addIncludePath(b.path("../../../c/tasks"));
    tests.root_module.addIncludePath(b.path("../../../c/ecs"));
    tests.root_module.addIncludePath(b.path("../../../c/math"));
    tests.root_module.addIncludePath(b.path("../../../c/result"));
    tests.root_module.addIncludePath(b.path("../../../c/scheduling"));
    tests.root_module.addIncludePath(b.path("../../scheduling/schedule/include"));
    tests.root_module.addIncludePath(b.path("../../common/include"));
    tests.root_module.addIncludePath(b.path("../../../c/configuration"));
    b.step("test", "Check the schedule ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
