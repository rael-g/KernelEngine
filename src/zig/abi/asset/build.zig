const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("asset.zig") });
    abi.addImport("render", b.dependency("ke_abi_render", .{}).module("abi"));
    abi.addImport("result", b.dependency("ke_abi_result", .{}).module("abi"));
    abi.addImport("task_pool", b.dependency("ke_abi_task_pool", .{}).module("abi"));
    abi.addImport("text", b.dependency("ke_abi_text", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/asset/asset_loader.h>
        \\#include <kernel_engine/asset/asset_resolver.h>
        \\#include <kernel_engine/asset/image_loader.h>
        \\#include <kernel_engine/asset/mesh_data.h>
        \\#include <kernel_engine/asset/mesh_shape.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../c/asset"));
    translated.addIncludePath(b.path("../../../c/ecs"));
    translated.addIncludePath(b.path("../../../c/math"));
    translated.addIncludePath(b.path("../../../c/render"));
    translated.addIncludePath(b.path("../../../c/result"));
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
    b.step("test", "Check the asset ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
