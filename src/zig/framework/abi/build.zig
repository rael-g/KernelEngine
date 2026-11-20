const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("framework_factory.zig") });
    abi.addImport("asset_resolver", b.dependency("abi_asset_resolver", .{}).module("abi"));
    abi.addImport("completion", b.dependency("abi_completion", .{}).module("abi"));
    abi.addImport("ecs", b.dependency("abi_ecs", .{}).module("abi"));
    abi.addImport("framework", b.dependency("abi_framework", .{}).module("abi"));
    abi.addImport("image_loader", b.dependency("abi_image_loader", .{}).module("abi"));
    abi.addImport("input", b.dependency("abi_input", .{}).module("abi"));
    abi.addImport("input_actions", b.dependency("abi_input_actions", .{}).module("abi"));
    abi.addImport("io", b.dependency("abi_io", .{}).module("abi"));
    abi.addImport("logger", b.dependency("abi_logger", .{}).module("abi"));
    abi.addImport("part", b.dependency("abi_part", .{}).module("abi"));
    abi.addImport("result", b.dependency("abi_result", .{}).module("abi"));
    abi.addImport("scene_tree", b.dependency("abi_scene_tree", .{}).module("abi"));
    abi.addImport("schedule", b.dependency("abi_schedule", .{}).module("abi"));
    abi.addImport("scheduler", b.dependency("abi_scheduler", .{}).module("abi"));
    abi.addImport("settings", b.dependency("abi_settings", .{}).module("abi"));
    abi.addImport("text", b.dependency("abi_text", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/framework/asset_resolver_create.h>
        \\#include <kernel_engine/framework/framework_log.h>
        \\#include <kernel_engine/framework/input_actions_create.h>
        \\#include <kernel_engine/framework/input_actions_evaluation_create.h>
        \\#include <kernel_engine/framework/scene_hierarchy_create.h>
        \\#include <kernel_engine/framework/scene_tree_create.h>
        \\#include <kernel_engine/framework/node_types_create.h>
        \\#include <kernel_engine/framework/node_types_systems_create.h>
        \\#include <kernel_engine/framework/scene_files_create.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../c/asset"));
    translated.addIncludePath(b.path("../../../c/async"));
    translated.addIncludePath(b.path("../../../c/completion"));
    translated.addIncludePath(b.path("../../../c/ecs"));
    translated.addIncludePath(b.path("../../../c/file_system"));
    translated.addIncludePath(b.path("../../../c/framework"));
    translated.addIncludePath(b.path("../include"));
    translated.addIncludePath(b.path("../../common/include"));
    translated.addIncludePath(b.path("../../../c/input"));
    translated.addIncludePath(b.path("../../input/default/include"));
    translated.addIncludePath(b.path("../../../c/io"));
    translated.addIncludePath(b.path("../../../c/job"));
    translated.addIncludePath(b.path("../../../c/logger"));
    translated.addIncludePath(b.path("../../../c/math"));
    translated.addIncludePath(b.path("../../../c/render"));
    translated.addIncludePath(b.path("../../../c/part"));
    translated.addIncludePath(b.path("../../../c/result"));
    translated.addIncludePath(b.path("../../../c/schedule"));
    translated.addIncludePath(b.path("../../schedule/include"));
    translated.addIncludePath(b.path("../../../c/scheduler"));
    translated.addIncludePath(b.path("../../scheduler/include"));
    translated.addIncludePath(b.path("../../../c/settings"));
    translated.addIncludePath(b.path("../../../c/spatial"));
    translated.addIncludePath(b.path("../../../c/text"));
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
    tests.root_module.addIncludePath(b.path("../../../c/asset"));
    tests.root_module.addIncludePath(b.path("../../../c/async"));
    tests.root_module.addIncludePath(b.path("../../../c/completion"));
    tests.root_module.addIncludePath(b.path("../../../c/ecs"));
    tests.root_module.addIncludePath(b.path("../../../c/file_system"));
    tests.root_module.addIncludePath(b.path("../../../c/framework"));
    tests.root_module.addIncludePath(b.path("../include"));
    tests.root_module.addIncludePath(b.path("../../common/include"));
    tests.root_module.addIncludePath(b.path("../../../c/input"));
    tests.root_module.addIncludePath(b.path("../../input/default/include"));
    tests.root_module.addIncludePath(b.path("../../../c/io"));
    tests.root_module.addIncludePath(b.path("../../../c/job"));
    tests.root_module.addIncludePath(b.path("../../../c/logger"));
    tests.root_module.addIncludePath(b.path("../../../c/math"));
    tests.root_module.addIncludePath(b.path("../../../c/render"));
    tests.root_module.addIncludePath(b.path("../../../c/part"));
    tests.root_module.addIncludePath(b.path("../../../c/result"));
    tests.root_module.addIncludePath(b.path("../../../c/schedule"));
    tests.root_module.addIncludePath(b.path("../../schedule/include"));
    tests.root_module.addIncludePath(b.path("../../../c/scheduler"));
    tests.root_module.addIncludePath(b.path("../../scheduler/include"));
    tests.root_module.addIncludePath(b.path("../../../c/settings"));
    tests.root_module.addIncludePath(b.path("../../../c/spatial"));
    tests.root_module.addIncludePath(b.path("../../../c/text"));
    b.step("test", "Check the framework_factory ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
