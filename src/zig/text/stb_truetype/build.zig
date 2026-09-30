const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_logger = b.option([]const u8, "ke-logger-include", "kernel_engine/logger include dir") orelse @panic("-Dke-logger-include required");
    const ke_text = b.option([]const u8, "ke-text-include", "kernel_engine/text include dir") orelse @panic("-Dke-text-include required");
    const ke_self = b.option([]const u8, "ke-self-include", "this plugin's include dir") orelse @panic("-Dke-self-include required");
    const stb_include = b.option([]const u8, "stb-include", "vcpkg stb_truetype.h include dir") orelse @panic("-Dstb-include required");

    const kerror_src = b.option([]const u8, "kerror-src", "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/stb_font.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_logger, ke_text, ke_self, stb_include }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addCSourceFile(.{ .file = b.path("src/stb_font_impl.c"), .flags = &.{"-fno-sanitize=undefined"} });
    const kerror_mod = b.createModule(.{ .root_source_file = .{ .cwd_relative = kerror_src }, .target = target, .optimize = optimize });
    mod.addImport("kerror", kerror_mod);
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

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/stb_font.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_logger, ke_text, ke_self, stb_include }) |inc| {
        test_mod.addIncludePath(.{ .cwd_relative = inc });
    }
    test_mod.addCSourceFile(.{ .file = b.path("src/stb_font_impl.c"), .flags = &.{"-fno-sanitize=undefined"} });
    test_mod.addImport("kerror", b.createModule(.{
        .root_source_file = .{ .cwd_relative = kerror_src },
        .target = target,
        .optimize = optimize,
    }));
    test_mod.addCMacro("KE_TEXT_STB_TRUETYPE_EXPORT", "");

    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    b.step("test", "Run the stb_truetype font loader unit tests").dependOn(&run_tests.step);
}
