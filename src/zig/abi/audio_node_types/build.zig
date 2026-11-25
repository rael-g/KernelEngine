const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("audio_node_types.zig") });
    abi.addImport("audio_components", b.dependency("abi_audio_components", .{}).module("abi"));
    abi.addImport("ecs", b.dependency("abi_ecs", .{}).module("abi"));
    abi.addImport("framework", b.dependency("abi_framework", .{}).module("abi"));
    abi.addImport("result", b.dependency("abi_result", .{}).module("abi"));
    abi.addImport("spatial", b.dependency("abi_spatial", .{}).module("abi"));
    abi.addImport("spatial_node_types", b.dependency("abi_spatial_node_types", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/audio/node_types.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../c/audio"));
    translated.addIncludePath(b.path("../../../c/ecs"));
    translated.addIncludePath(b.path("../../../c/framework"));
    translated.addIncludePath(b.path("../../../c/math"));
    translated.addIncludePath(b.path("../../../c/result"));
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
    tests.root_module.addIncludePath(b.path("../../../c/audio"));
    tests.root_module.addIncludePath(b.path("../../../c/ecs"));
    tests.root_module.addIncludePath(b.path("../../../c/framework"));
    tests.root_module.addIncludePath(b.path("../../../c/math"));
    tests.root_module.addIncludePath(b.path("../../../c/result"));
    b.step("test", "Check the audio_node_types ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
