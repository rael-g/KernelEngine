const std = @import("std");

// Build the ke_text_stb_truetype shared library (Zig 0.16 API).
// A standalone plugin: bakes a glyph atlas via the vendored stb_truetype.h
// (vcpkg). Allocates through Zig's own allocator (std.heap.c_allocator),
// same choice as ke_asset_stb_image.

pub fn build(b: *std.Build) void {
    // GNU ABI (Zig's Windows default), matching every other Zig plugin. Safe
    // because nothing MSVC-built is linked into this module: the only C is
    // stb_truetype's header-only implementation, which Zig compiles itself;
    // ke_common is consumed across a plain C-ABI DLL boundary (ABI-neutral).
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_logger = b.option([]const u8, "ke-logger-include", "kernel_engine/logger include dir") orelse @panic("-Dke-logger-include required");
    const ke_text = b.option([]const u8, "ke-text-include", "kernel_engine/text include dir") orelse @panic("-Dke-text-include required");
    const ke_self = b.option([]const u8, "ke-self-include", "this plugin's include dir") orelse @panic("-Dke-self-include required");
    const stb_include = b.option([]const u8, "stb-include", "vcpkg stb_truetype.h include dir") orelse @panic("-Dstb-include required");
    const ke_lib_dir = b.option([]const u8, "ke-lib-dir", "dir with ke_common import lib") orelse @panic("-Dke-lib-dir required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/stb_font.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_logger, ke_text, ke_self, stb_include }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    // stb_truetype is header-only: this is the one translation unit that
    // compiles the implementation. @cImport only ever sees the declarations —
    // translate-c cannot lower stb's internals.
    // -fno-sanitize=undefined: stb does pointer arithmetic the Debug UBSan flags
    // as UB; it is not our code to fix.
    mod.addCSourceFile(.{ .file = b.path("src/stb_font_impl.c"), .flags = &.{"-fno-sanitize=undefined"} });
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.addCMacro("KE_TEXT_STB_TRUETYPE_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_text_stb_truetype",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
