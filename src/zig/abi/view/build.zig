const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("view.zig") });
    abi.addImport("math", b.dependency("ke_abi_math", .{}).module("abi"));
    abi.addImport("render", b.dependency("ke_abi_render", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/view/view_space.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../c/ecs"));
    translated.addIncludePath(b.path("../../../c/math"));
    translated.addIncludePath(b.path("../../../c/render"));
    translated.addIncludePath(b.path("../../../c/result"));
    translated.addIncludePath(b.path("../../../c/spatial"));
    translated.addIncludePath(b.path("../../../c/view"));
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
    b.step("test", "Check the view ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
