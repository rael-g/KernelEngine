const std = @import("std");
const ke_common_build = @import("ke_common");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scene_components_src = b.option([]const u8, "scene-components-src", "path to the shared Zig scene_components.zig") orelse @panic("-Dscene-components-src required");

    const ke_common    = b.option([]const u8, "ke-common-include",    "kernel_engine/common include dir")    orelse @panic("-Dke-common-include required");
    const ke_math = b.option([]const u8, "ke-math-include", "kernel_engine/math include dir") orelse @panic("-Dke-math-include required");
    const ke_ecs       = b.option([]const u8, "ke-ecs-include",       "kernel_engine/ecs include dir")       orelse @panic("-Dke-ecs-include required");
    const ke_audio     = b.option([]const u8, "ke-audio-include",     "kernel_engine/audio include dir")     orelse @panic("-Dke-audio-include required");
    const ke_spatial   = b.option([]const u8, "ke-spatial-include",   "kernel_engine/spatial include dir")   orelse @panic("-Dke-spatial-include required");
    const ke_runtime   = b.option([]const u8, "ke-runtime-include",   "kernel_engine/runtime include dir")   orelse @panic("-Dke-runtime-include required");
    const ke_framework = b.option([]const u8, "ke-framework-include", "kernel_engine/framework include dir") orelse @panic("-Dke-framework-include required");
    const ke_self      = b.option([]const u8, "ke-self-include",      "this plugin's include dir")           orelse @panic("-Dke-self-include required");
    const ke_lib_dir   = b.option([]const u8, "ke-lib-dir",           "dir with ke_common import lib")       orelse @panic("-Dke-lib-dir required");
    const stubs_src    = b.option([]const u8, "stubs-src",            "path to the shared Zig stubs.zig")    orelse @panic("-Dstubs-src required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/audio_module.zig"),
        .target    = target,
        .optimize  = optimize,
        .link_libc = true,
    });
    mod.addImport("scene_components", b.createModule(.{ .root_source_file = .{ .cwd_relative = scene_components_src }, .target = target, .optimize = optimize }));
    inline for (.{ ke_common, ke_math, ke_ecs, ke_audio, ke_spatial, ke_runtime, ke_framework, ke_self }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.addRPathSpecial("$ORIGIN");
    mod.addCMacro("KE_AUDIO_MODULE_EXPORT", "");

    mod.addImport("c", ke_common_build.cImports(b, mod, b.path("src/c.h")));
    const lib = b.addLibrary(.{
        .name = "ke_audio_module",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/audio_module.zig"),
        .target    = target,
        .optimize  = optimize,
        .link_libc = true,
    });
    test_mod.addImport("scene_components", b.createModule(.{ .root_source_file = .{ .cwd_relative = scene_components_src }, .target = target, .optimize = optimize }));
    inline for (.{ ke_common, ke_math, ke_ecs, ke_audio, ke_spatial, ke_runtime, ke_framework, ke_self }) |inc| {
        test_mod.addIncludePath(.{ .cwd_relative = inc });
    }
    test_mod.addImport("stubs", b.createModule(.{ .root_source_file = .{ .cwd_relative = stubs_src }, .target = target, .optimize = optimize }));
    test_mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    test_mod.linkSystemLibrary("ke_common", .{});
    test_mod.addCMacro("KE_AUDIO_MODULE_EXPORT", "");

    test_mod.addImport("c", ke_common_build.cImports(b, test_mod, b.path("src/c.h")));
    const unit_tests = b.addTest(.{ .root_module = test_mod });
    b.step("test", "Run the audio module unit tests").dependOn(&b.addRunArtifact(unit_tests).step);
}
