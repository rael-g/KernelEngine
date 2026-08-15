const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_asset = b.option([]const u8, "ke-asset-include", "kernel_engine/asset include dir") orelse @panic("-Dke-asset-include required");
    const ke_logger = b.option([]const u8, "ke-logger-include", "kernel_engine/logger include dir") orelse @panic("-Dke-logger-include required");
    const ke_render = b.option([]const u8, "ke-render-include", "kernel_engine/render include dir") orelse @panic("-Dke-render-include required");
    const ke_scheduler = b.option([]const u8, "ke-scheduler-include", "kernel_engine/scheduler include dir") orelse @panic("-Dke-scheduler-include required");
    const assimp_include = b.option([]const u8, "assimp-include", "Assimp headers dir") orelse @panic("-Dassimp-include required");
    const assimp_libs = b.option([]const u8, "assimp-libs", "'|'-separated Assimp library paths") orelse @panic("-Dassimp-libs required");
    const stb_include = b.option([]const u8, "stb-include", "vcpkg stb_image.h include dir") orelse @panic("-Dstb-include required");
    const kerror_src = b.option([]const u8, "kerror-src", "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/assimp_loader.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    inline for (.{ ke_common, ke_asset, ke_logger, ke_render, ke_scheduler, assimp_include, stb_include }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addIncludePath(b.path("include"));

    var lib_it = std.mem.splitScalar(u8, assimp_libs, '|');
    while (lib_it.next()) |lib| {
        if (lib.len != 0) mod.addObjectFile(.{ .cwd_relative = lib });
    }

    const kerror_mod = b.createModule(.{
        .root_source_file = .{ .cwd_relative = kerror_src },
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("kerror", kerror_mod);
    mod.addCMacro("KE_ASSET_ASSIMP_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_asset_assimp",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/assimp_loader.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    inline for (.{ ke_common, ke_asset, ke_logger, ke_render, ke_scheduler, assimp_include, stb_include }) |inc| {
        test_mod.addIncludePath(.{ .cwd_relative = inc });
    }
    test_mod.addIncludePath(b.path("include"));
    var test_lib_it = std.mem.splitScalar(u8, assimp_libs, '|');
    while (test_lib_it.next()) |lib_path| {
        if (lib_path.len != 0) test_mod.addObjectFile(.{ .cwd_relative = lib_path });
    }
    test_mod.addImport("kerror", b.createModule(.{
        .root_source_file = .{ .cwd_relative = kerror_src },
        .target = target,
        .optimize = optimize,
    }));
    test_mod.addCMacro("KE_ASSET_ASSIMP_EXPORT", "");

    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    b.step("test", "Run the assimp conversion unit tests").dependOn(&run_tests.step);
}
