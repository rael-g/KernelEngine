const std = @import("std");

// Build the ke_audio_module shared library (Zig 0.16 API).
// Audio's domain-level scene vocabulary: it teaches a ke_world what an
// audio_player component is. Talks to everything through borrowed
// ke_ecs/ke_world handles, so it links no audio backend and is built against
// none — swapping miniaudio out never touches this plugin.

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common    = b.option([]const u8, "ke-common-include",    "kernel_engine/common include dir")    orelse @panic("-Dke-common-include required");
    const ke_ecs       = b.option([]const u8, "ke-ecs-include",       "kernel_engine/ecs include dir")       orelse @panic("-Dke-ecs-include required");
    const ke_audio     = b.option([]const u8, "ke-audio-include",     "kernel_engine/audio include dir")     orelse @panic("-Dke-audio-include required");
    const ke_spatial   = b.option([]const u8, "ke-spatial-include",   "kernel_engine/spatial include dir")   orelse @panic("-Dke-spatial-include required");
    const ke_runtime   = b.option([]const u8, "ke-runtime-include",   "kernel_engine/runtime include dir")   orelse @panic("-Dke-runtime-include required");
    const ke_framework = b.option([]const u8, "ke-framework-include", "kernel_engine/framework include dir") orelse @panic("-Dke-framework-include required");
    const ke_self      = b.option([]const u8, "ke-self-include",      "this plugin's include dir")           orelse @panic("-Dke-self-include required");
    const ke_lib_dir   = b.option([]const u8, "ke-lib-dir",           "dir with ke_common import lib")       orelse @panic("-Dke-lib-dir required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/audio_module.zig"),
        .target    = target,
        .optimize  = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_ecs, ke_audio, ke_spatial, ke_runtime, ke_framework, ke_self }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.addCMacro("KE_AUDIO_MODULE_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_audio_module",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
