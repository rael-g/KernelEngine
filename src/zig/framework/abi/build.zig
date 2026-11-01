const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("framework_factory.zig") });
    abi.addImport("world", b.dependency("abi_world", .{}).module("abi"));
    abi.addImport("signal_bus", b.dependency("abi_signal_bus", .{}).module("abi"));
    abi.addImport("script_host", b.dependency("abi_script_host", .{}).module("abi"));
    abi.addImport("scene_tree", b.dependency("abi_scene_tree", .{}).module("abi"));
    abi.addImport("scene_loader", b.dependency("abi_scene_loader", .{}).module("abi"));
    abi.addImport("input_actions", b.dependency("abi_input_actions", .{}).module("abi"));
    abi.addImport("image_loader", b.dependency("abi_image_loader", .{}).module("abi"));
    abi.addImport("asset_resolver", b.dependency("abi_asset_resolver", .{}).module("abi"));
    abi.addImport("ecs", b.dependency("ke_abi_ecs", .{}).module("abi"));
    abi.addImport("framework", b.dependency("ke_abi_framework", .{}).module("abi"));
    abi.addImport("io", b.dependency("ke_abi_io", .{}).module("abi"));
    abi.addImport("logger", b.dependency("ke_abi_logger", .{}).module("abi"));
    abi.addImport("result", b.dependency("ke_abi_result", .{}).module("abi"));
    abi.addImport("runtime", b.dependency("ke_abi_runtime", .{}).module("abi"));
    abi.addImport("text", b.dependency("ke_abi_text", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/framework/asset_resolver_create.h>
        \\#include <kernel_engine/framework/framework_log.h>
        \\#include <kernel_engine/framework/input_actions_create.h>
        \\#include <kernel_engine/framework/scene_component_set_create.h>
        \\#include <kernel_engine/framework/scene_hierarchy_create.h>
        \\#include <kernel_engine/framework/scene_loader_create.h>
        \\#include <kernel_engine/framework/scene_tree_create.h>
        \\#include <kernel_engine/framework/script_host_create.h>
        \\#include <kernel_engine/framework/signal_bus_create.h>
        \\#include <kernel_engine/framework/world_create.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../c/asset"));
    translated.addIncludePath(b.path("../../../c/ecs"));
    translated.addIncludePath(b.path("../../../c/file_system"));
    translated.addIncludePath(b.path("../../../c/framework"));
    translated.addIncludePath(b.path("../include"));
    translated.addIncludePath(b.path("../../../c/input"));
    translated.addIncludePath(b.path("../../../c/io"));
    translated.addIncludePath(b.path("../../../c/logger"));
    translated.addIncludePath(b.path("../../../c/math"));
    translated.addIncludePath(b.path("../../../c/render"));
    translated.addIncludePath(b.path("../../../c/result"));
    translated.addIncludePath(b.path("../../../c/runtime"));
    translated.addIncludePath(b.path("../../../c/spatial"));
    translated.addIncludePath(b.path("../../../c/task_pool"));
    translated.addIncludePath(b.path("../../../c/text"));
    translated.addIncludePath(b.path("../../common/include"));
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("layout_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "abi", .module = abi },
            .{ .name = "c", .module = translated.createModule() },
        },
    }) });
    b.step("test", "Check the framework_factory ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
