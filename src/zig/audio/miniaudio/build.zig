const std = @import("std");

// Build the ke_audio_miniaudio shared library (Zig 0.16 API).
// A standalone plugin: plays sounds via the vendored miniaudio.h (vcpkg),
// dedups through ke_resource_cache_default (a real DLL, like ke_common).
// Allocates through Zig's own allocator (std.heap.c_allocator).

pub fn build(b: *std.Build) void {
    // GNU ABI (Zig's Windows default), matching every other Zig plugin. Safe
    // because nothing MSVC-built is linked into this module: the only C is
    // miniaudio's header-only implementation, which Zig compiles itself;
    // ke_common / ke_resource_cache_default are consumed across plain C-ABI DLL
    // boundaries (ABI-neutral).
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_logger = b.option([]const u8, "ke-logger-include", "kernel_engine/logger include dir") orelse @panic("-Dke-logger-include required");
    const ke_audio = b.option([]const u8, "ke-audio-include", "kernel_engine/audio include dir") orelse @panic("-Dke-audio-include required");
    const ke_resource_cache = b.option([]const u8, "ke-resource-cache-include", "kernel_engine/resource_cache include dir") orelse @panic("-Dke-resource-cache-include required");
    const ke_self = b.option([]const u8, "ke-self-include", "this plugin's include dir") orelse @panic("-Dke-self-include required");
    const miniaudio_include = b.option([]const u8, "miniaudio-include", "vcpkg miniaudio.h include dir") orelse @panic("-Dminiaudio-include required");
    const ke_lib_dir = b.option([]const u8, "ke-lib-dir", "dir with ke_common import lib") orelse @panic("-Dke-lib-dir required");
    const ke_resource_cache_lib_dir = b.option([]const u8, "ke-resource-cache-lib-dir", "dir with ke_resource_cache_default import lib") orelse @panic("-Dke-resource-cache-lib-dir required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/miniaudio_audio.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_logger, ke_audio, ke_resource_cache, ke_self, miniaudio_include }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    // miniaudio is header-only: this is the one translation unit that compiles
    // the implementation. @cImport only ever sees the declarations.
    // -fno-sanitize=undefined: miniaudio (like most battle-tested C) does
    // pointer arithmetic the Debug UBSan flags as UB; it is not our code to fix.
    mod.addCSourceFile(.{ .file = b.path("src/miniaudio_impl.c"), .flags = &.{"-fno-sanitize=undefined"} });
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.addLibraryPath(.{ .cwd_relative = ke_resource_cache_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.linkSystemLibrary("ke_resource_cache_default", .{});
    // miniaudio uses the OS audio APIs; on Windows that's WASAPI/DSound and
    // brings in winmm — same as the C++ plugin's IF(WIN32) link.
    if (target.result.os.tag == .windows) {
        mod.linkSystemLibrary("winmm", .{});
    }
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
}
