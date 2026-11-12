const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi = b.addModule("abi", .{ .root_source_file = b.path("configuration_toml_factory.zig") });
    abi.addImport("configuration", b.dependency("abi_configuration", .{}).module("abi"));
    abi.addImport("io", b.dependency("abi_io", .{}).module("abi"));
    abi.addImport("logger", b.dependency("abi_logger", .{}).module("abi"));
    abi.addImport("result", b.dependency("abi_result", .{}).module("abi"));

    const headers = b.addWriteFiles().add("layout.h",
        \\#include <kernel_engine/configuration/toml/configuration_toml.h>
        \\#include <kernel_engine/configuration/toml/configuration_toml_log.h>
    );
    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });
    translated.addIncludePath(b.path("../../../../c/configuration"));
    translated.addIncludePath(b.path("../include"));
    translated.addIncludePath(b.path("../../../common/include"));
    translated.addIncludePath(b.path("../../../../c/file_system"));
    translated.addIncludePath(b.path("../../../../c/io"));
    translated.addIncludePath(b.path("../../../../c/logger"));
    translated.addIncludePath(b.path("../../../../c/result"));
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
    tests.root_module.addIncludePath(b.path("../../../../c/configuration"));
    tests.root_module.addIncludePath(b.path("../include"));
    tests.root_module.addIncludePath(b.path("../../../common/include"));
    tests.root_module.addIncludePath(b.path("../../../../c/file_system"));
    tests.root_module.addIncludePath(b.path("../../../../c/io"));
    tests.root_module.addIncludePath(b.path("../../../../c/logger"));
    tests.root_module.addIncludePath(b.path("../../../../c/result"));
    b.step("test", "Check the configuration_toml_factory ABI against its headers").dependOn(&b.addRunArtifact(tests).step);
}
