const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("framework.zig") });
    abi.addImport("ecs", b.dependency("ke_abi_ecs", .{}).module("abi"));
    abi.addImport("input", b.dependency("ke_abi_input", .{}).module("abi"));
    abi.addImport("result", b.dependency("ke_abi_result", .{}).module("abi"));
    abi.addImport("runtime", b.dependency("ke_abi_runtime", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/framework/components.h>
        \\#include <kernel_engine/framework/input_actions.h>
        \\#include <kernel_engine/framework/scene_component_set.h>
        \\#include <kernel_engine/framework/scene_hierarchy.h>
        \\#include <kernel_engine/framework/scene_loader.h>
        \\#include <kernel_engine/framework/scene_tree.h>
        \\#include <kernel_engine/framework/script_host.h>
        \\#include <kernel_engine/framework/signal_bus.h>
        \\#include <kernel_engine/framework/world.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../c/ecs"));
    translated.addIncludePath(b.path("../../../c/framework"));
    translated.addIncludePath(b.path("../../../c/input"));
    translated.addIncludePath(b.path("../../../c/math"));
    translated.addIncludePath(b.path("../../../c/result"));
    translated.addIncludePath(b.path("../../../c/runtime"));
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
    b.step("test", "Check the framework ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
