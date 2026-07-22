const std = @import("std");

// Build the ke_asset_stb_image shared library (Zig 0.16 API).
// A standalone plugin: decodes images via the vendored stb_image.h (vcpkg).
// Allocates through Zig's own allocator, not a C/C++ one.

pub fn build(b: *std.Build) void {
    // GNU ABI (Zig's Windows default), matching every other Zig plugin in the
    // tree. Safe because nothing MSVC-built is linked *into* this module: the
    // only C here is stb_image's header-only implementation, which Zig compiles
    // itself. ke_common is consumed across a plain C-ABI DLL boundary, which is
    // ABI-neutral.
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_logger = b.option([]const u8, "ke-logger-include", "kernel_engine/logger include dir") orelse @panic("-Dke-logger-include required");
    const ke_render = b.option([]const u8, "ke-render-include", "kernel_engine/render include dir") orelse @panic("-Dke-render-include required");
    const ke_asset = b.option([]const u8, "ke-asset-include", "kernel_engine/asset include dir") orelse @panic("-Dke-asset-include required");
    const ke_self = b.option([]const u8, "ke-self-include", "this plugin's include dir") orelse @panic("-Dke-self-include required");
    const stb_include = b.option([]const u8, "stb-include", "vcpkg stb_image.h include dir") orelse @panic("-Dstb-include required");

    const kerror_src = b.option([]const u8, "kerror-src", "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/stb_image_loader.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_logger, ke_render, ke_asset, ke_self, stb_include }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    // stb_image is header-only: this is the one translation unit that compiles
    // the implementation. @cImport only ever sees the declarations — translate-c
    // cannot lower stb's JPEG decoder.
    // -fno-sanitize=undefined: stb does pointer arithmetic the Debug UBSan flags
    // as UB; it is not our code to fix.
    mod.addCSourceFile(.{ .file = b.path("src/stb_image_impl.c"), .flags = &.{"-fno-sanitize=undefined"} });
    const kerror_mod = b.createModule(.{ .root_source_file = .{ .cwd_relative = kerror_src }, .target = target, .optimize = optimize });
    mod.addImport("kerror", kerror_mod);
    mod.addCMacro("KE_ASSET_STB_IMAGE_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_asset_stb_image",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
