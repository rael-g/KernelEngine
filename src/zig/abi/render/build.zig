const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("render.zig") });
    abi.addImport("ecs", b.dependency("ke_abi_ecs", .{}).module("abi"));
    abi.addImport("math", b.dependency("ke_abi_math", .{}).module("abi"));
    abi.addImport("result", b.dependency("ke_abi_result", .{}).module("abi"));
    abi.addImport("spatial", b.dependency("ke_abi_spatial", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/render/binding/resource_binder.h>
        \\#include <kernel_engine/render/camera.h>
        \\#include <kernel_engine/render/component_fields.h>
        \\#include <kernel_engine/render/components.h>
        \\#include <kernel_engine/render/gpu/gpu_commands.h>
        \\#include <kernel_engine/render/gpu/gpu_device.h>
        \\#include <kernel_engine/render/gpu/gpu_enums.h>
        \\#include <kernel_engine/render/gpu/gpu_render_target.h>
        \\#include <kernel_engine/render/gpu/ndc_convention.h>
        \\#include <kernel_engine/render/handles.h>
        \\#include <kernel_engine/render/material_file.h>
        \\#include <kernel_engine/render/mesh.h>
        \\#include <kernel_engine/render/resource_groups.h>
        \\#include <kernel_engine/render/service/pass_context.h>
        \\#include <kernel_engine/render/service/render_service.h>
        \\#include <kernel_engine/render/ui/component_fields.h>
        \\#include <kernel_engine/render/ui/components.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../c/ecs"));
    translated.addIncludePath(b.path("../../../c/math"));
    translated.addIncludePath(b.path("../../../c/render"));
    translated.addIncludePath(b.path("../../../c/result"));
    translated.addIncludePath(b.path("../../../c/spatial"));
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
    b.step("test", "Check the render ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
