const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("engine_node_types.zig") });
    abi.addImport("audio_components", b.dependency("abi_audio_components", .{}).module("abi"));
    abi.addImport("ecs", b.dependency("abi_ecs", .{}).module("abi"));
    abi.addImport("framework", b.dependency("abi_framework", .{}).module("abi"));
    abi.addImport("physics_components", b.dependency("abi_physics_components", .{}).module("abi"));
    abi.addImport("render_components", b.dependency("abi_render_components", .{}).module("abi"));
    abi.addImport("render_contract", b.dependency("abi_render_contract", .{}).module("abi"));
    abi.addImport("render_material", b.dependency("abi_render_material", .{}).module("abi"));
    abi.addImport("result", b.dependency("abi_result", .{}).module("abi"));
    abi.addImport("spatial", b.dependency("abi_spatial", .{}).module("abi"));
    abi.addImport("ui_components", b.dependency("abi_ui_components", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/engine_nodes/engine_node_types.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../c/audio"));
    translated.addIncludePath(b.path("../../../c/ecs"));
    translated.addIncludePath(b.path("../../../c/engine_nodes"));
    translated.addIncludePath(b.path("../../../c/framework"));
    translated.addIncludePath(b.path("../../../c/math"));
    translated.addIncludePath(b.path("../../../c/physics"));
    translated.addIncludePath(b.path("../../../c/render"));
    translated.addIncludePath(b.path("../../../c/asset"));
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
    tests.root_module.addIncludePath(b.path("../../../c/engine_nodes"));
    tests.root_module.addIncludePath(b.path("../../../c/framework"));
    tests.root_module.addIncludePath(b.path("../../../c/math"));
    tests.root_module.addIncludePath(b.path("../../../c/physics"));
    tests.root_module.addIncludePath(b.path("../../../c/render"));
    tests.root_module.addIncludePath(b.path("../../../c/asset"));
    tests.root_module.addIncludePath(b.path("../../../c/result"));
    b.step("test", "Check the engine_node_types ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
