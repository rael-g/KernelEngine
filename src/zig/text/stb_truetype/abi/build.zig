const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("text_stb_truetype_factory.zig") });
    abi.addImport("io", b.dependency("ke_abi_io", .{}).module("abi"));
    abi.addImport("logger", b.dependency("ke_abi_logger", .{}).module("abi"));
    abi.addImport("result", b.dependency("ke_abi_result", .{}).module("abi"));
    abi.addImport("text", b.dependency("ke_abi_text", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/text/stb_truetype/stb_font.h>
        \\#include <kernel_engine/text/stb_truetype/text_stb_truetype_log.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../../c/file_system"));
    translated.addIncludePath(b.path("../../../../c/io"));
    translated.addIncludePath(b.path("../../../../c/logger"));
    translated.addIncludePath(b.path("../../../../c/result"));
    translated.addIncludePath(b.path("../../../../c/text"));
    translated.addIncludePath(b.path("../include"));
    translated.addIncludePath(b.path("../../../common/include"));
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("layout_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "abi", .module = abi },
            .{ .name = "c", .module = translated.createModule() },
        },
    }) });
    b.step("test", "Check the text_stb_truetype_factory ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
