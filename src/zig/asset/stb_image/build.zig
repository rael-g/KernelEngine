const std = @import("std");
const ke_build = @import("ke_build");
const ke_logger_build = @import("ke_logger");
const ke_result_build = @import("ke_result");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_result = b.option([]const u8, "ke-result-include", "kernel_engine/result include dir") orelse @panic("-Dke-result-include required");
    const heap_src = b.option([]const u8, "heap-src", "path to the shared Zig heap.zig") orelse @panic("-Dheap-src required");
    const ke_logger = b.option([]const u8, "ke-logger-include", "kernel_engine/logger include dir") orelse @panic("-Dke-logger-include required");
    const ke_render = b.option([]const u8, "ke-render-include", "kernel_engine/render include dir") orelse @panic("-Dke-render-include required");
    const ke_asset = b.option([]const u8, "ke-asset-include", "kernel_engine/asset include dir") orelse @panic("-Dke-asset-include required");
    const ke_self = b.option([]const u8, "ke-self-include", "this plugin's include dir") orelse @panic("-Dke-self-include required");
    const stb_include = b.option([]const u8, "stb-include", "vcpkg stb_image.h include dir") orelse @panic("-Dstb-include required");



    const mod = b.createModule(.{
        .root_source_file = b.path("src/stb_image_loader.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    inline for (.{ ke_common, ke_result, ke_logger, ke_render, ke_asset, ke_self, stb_include }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    const implementation = b.addWriteFiles().add("stb_image_impl.c", "#define STB_IMAGE_IMPLEMENTATION\n#include <stb_image.h>\n");
    mod.addCSourceFile(.{ .file = implementation, .flags = &.{ "-fno-sanitize=undefined", "-Werror", "-Wno-unused-command-line-argument" } });
    mod.addImport("dll_entry", ke_result_build.dllEntry(b));
    mod.addImport("log", ke_logger_build.log(b));
    mod.addImport("result", ke_result_build.result(b));
    mod.addCMacro("KE_ASSET_STB_IMAGE_EXPORT", "");

    mod.addImport("c", ke_build.cImports(b, mod, b.path("src/c.h")));
    const lib = b.addLibrary(.{
        .name = "ke_asset_stb_image",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/stb_image_loader.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    inline for (.{ ke_common, ke_result, ke_logger, ke_render, ke_asset, ke_self, stb_include }) |inc| {
        test_mod.addIncludePath(.{ .cwd_relative = inc });
    }
    test_mod.addCSourceFile(.{ .file = implementation, .flags = &.{ "-fno-sanitize=undefined", "-Werror", "-Wno-unused-command-line-argument" } });
    test_mod.addImport("dll_entry", ke_result_build.dllEntry(b));
    test_mod.addImport("log", ke_logger_build.log(b));
    test_mod.addImport("result", ke_result_build.result(b));
    test_mod.addCMacro("KE_ASSET_STB_IMAGE_EXPORT", "");

    test_mod.addImport("c", ke_build.cImports(b, test_mod, b.path("src/c.h")));
    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    b.step("test", "Run the stb_image loader unit tests").dependOn(&run_tests.step);
}
