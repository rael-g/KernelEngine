const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("window_glfw_factory.zig") });
    abi.addImport("input", b.dependency("abi_input", .{}).module("abi"));
    abi.addImport("logger", b.dependency("abi_logger", .{}).module("abi"));
    abi.addImport("result", b.dependency("abi_result", .{}).module("abi"));
    abi.addImport("settings", b.dependency("abi_settings", .{}).module("abi"));
    abi.addImport("window", b.dependency("abi_window", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/window/glfw/glfw_window.h>
        \\#include <kernel_engine/window/glfw/window_glfw_log.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../../c/input"));
    translated.addIncludePath(b.path("../../../input/default/include"));
    translated.addIncludePath(b.path("../../../common/include"));
    translated.addIncludePath(b.path("../../../../c/logger"));
    translated.addIncludePath(b.path("../../../../c/math"));
    translated.addIncludePath(b.path("../../../../c/result"));
    translated.addIncludePath(b.path("../../../../c/settings"));
    translated.addIncludePath(b.path("../../../../c/window"));
    translated.addIncludePath(b.path("../include"));
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
    tests.root_module.addIncludePath(b.path("../../../../c/input"));
    tests.root_module.addIncludePath(b.path("../../../input/default/include"));
    tests.root_module.addIncludePath(b.path("../../../common/include"));
    tests.root_module.addIncludePath(b.path("../../../../c/logger"));
    tests.root_module.addIncludePath(b.path("../../../../c/math"));
    tests.root_module.addIncludePath(b.path("../../../../c/result"));
    tests.root_module.addIncludePath(b.path("../../../../c/settings"));
    tests.root_module.addIncludePath(b.path("../../../../c/window"));
    tests.root_module.addIncludePath(b.path("../include"));
    b.step("test", "Check the window_glfw_factory ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
