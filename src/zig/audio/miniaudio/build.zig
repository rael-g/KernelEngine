const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const heap_src = b.option([]const u8, "heap-src", "path to the shared Zig heap.zig") orelse @panic("-Dheap-src required");
    const ke_logger = b.option([]const u8, "ke-logger-include", "kernel_engine/logger include dir") orelse @panic("-Dke-logger-include required");
    const ke_audio = b.option([]const u8, "ke-audio-include", "kernel_engine/audio include dir") orelse @panic("-Dke-audio-include required");
    const ke_resource_cache = b.option([]const u8, "ke-resource-cache-include", "kernel_engine/resource_cache include dir") orelse @panic("-Dke-resource-cache-include required");
    const ke_resource_cache_default = b.option([]const u8, "ke-resource-cache-default-include", "ke_resource_cache_default factory include dir") orelse @panic("-Dke-resource-cache-default-include required");
    const ke_self = b.option([]const u8, "ke-self-include", "this plugin's include dir") orelse @panic("-Dke-self-include required");
    const miniaudio_include = b.option([]const u8, "miniaudio-include", "vcpkg miniaudio.h include dir") orelse @panic("-Dminiaudio-include required");
    const ke_resource_cache_lib_dir = b.option([]const u8, "ke-resource-cache-lib-dir", "dir with ke_resource_cache_default import lib") orelse @panic("-Dke-resource-cache-lib-dir required");

    const kerror_src = b.option([]const u8, "kerror-src", "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/miniaudio_audio.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    inline for (.{ ke_common, ke_logger, ke_audio, ke_resource_cache, ke_resource_cache_default, ke_self, miniaudio_include }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addCSourceFile(.{ .file = b.path("src/miniaudio_impl.c"), .flags = &.{"-fno-sanitize=undefined"} });
    mod.addLibraryPath(.{ .cwd_relative = ke_resource_cache_lib_dir });
    mod.linkSystemLibrary("ke_resource_cache_default", .{});
    if (target.result.os.tag == .windows) {
        mod.linkSystemLibrary("winmm", .{});
    }
    const kerror_mod = b.createModule(.{ .root_source_file = .{ .cwd_relative = kerror_src }, .target = target, .optimize = optimize });
    mod.addImport("kerror", kerror_mod);
    mod.addCMacro("KE_AUDIO_MINIAUDIO_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_audio_miniaudio",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/miniaudio_audio.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    inline for (.{ ke_common, ke_logger, ke_audio, ke_resource_cache, ke_resource_cache_default, ke_self, miniaudio_include }) |inc| {
        test_mod.addIncludePath(.{ .cwd_relative = inc });
    }
    test_mod.addCSourceFile(.{ .file = b.path("src/miniaudio_impl.c"), .flags = &.{"-fno-sanitize=undefined"} });
    test_mod.addLibraryPath(.{ .cwd_relative = ke_resource_cache_lib_dir });
    test_mod.addRPath(.{ .cwd_relative = ke_resource_cache_lib_dir });
    test_mod.linkSystemLibrary("ke_resource_cache_default", .{});
    if (target.result.os.tag == .windows) {
        test_mod.linkSystemLibrary("winmm", .{});
    }
    test_mod.addImport("kerror", b.createModule(.{
        .root_source_file = .{ .cwd_relative = kerror_src },
        .target = target,
        .optimize = optimize,
    }));
    test_mod.addCMacro("KE_AUDIO_MINIAUDIO_EXPORT", "");

    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    b.step("test", "Run the miniaudio audio unit tests").dependOn(&run_tests.step);
}
