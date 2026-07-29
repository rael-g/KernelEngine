const std = @import("std");

// Build the ke_asset_assimp shared library (Zig 0.16 API) — model loading via
// Assimp's C API, so this module is Zig end to end even though Assimp itself
// is C++ (which is why its C++ runtime is linked). No ke_common LINK — the
// common headers are @cImport'd for the ke_error layout only and errors
// translate at the export seam via the shared Zig kerror utility.

pub fn build(b: *std.Build) void {
    // Plain native target: pinning the abi would make Zig treat this as a cross
    // build and stop searching the host paths where the C++ runtime lives.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_asset = b.option([]const u8, "ke-asset-include", "kernel_engine/asset include dir") orelse @panic("-Dke-asset-include required");
    const ke_logger = b.option([]const u8, "ke-logger-include", "kernel_engine/logger include dir") orelse @panic("-Dke-logger-include required");
    const ke_render = b.option([]const u8, "ke-render-include", "kernel_engine/render include dir") orelse @panic("-Dke-render-include required");
    const ke_scheduler = b.option([]const u8, "ke-scheduler-include", "kernel_engine/scheduler include dir") orelse @panic("-Dke-scheduler-include required");
    // Header path only: scheduler.h includes allocator.h. No allocator
    // implementation is compiled in — this plugin owns its memory through a
    const assimp_include = b.option([]const u8, "assimp-include", "Assimp headers dir") orelse @panic("-Dassimp-include required");
    // "|"-separated absolute paths: Assimp plus the static libraries it depends
    // on, resolved by the build system so this file carries no vcpkg layout.
    const assimp_libs = b.option([]const u8, "assimp-libs", "'|'-separated Assimp library paths") orelse @panic("-Dassimp-libs required");
    const stb_include = b.option([]const u8, "stb-include", "vcpkg stb_image.h include dir") orelse @panic("-Dstb-include required");
    const kerror_src = b.option([]const u8, "kerror-src", "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/assimp_loader.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        // Assimp is built against Zig's bundled libc++; this .so must embed
        // and export the same runtime for downstream consumers.
        .link_libcpp = true,
    });
    inline for (.{ ke_common, ke_asset, ke_logger, ke_render, ke_scheduler, assimp_include, stb_include }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addIncludePath(b.path("include"));

    // No stb_image implementation of our own: Assimp's static library already
    // contains one and exports stbi_load/stbi_load_from_memory/stbi_image_free,
    // so the header supplies the declarations and the definitions resolve from
    // the library we already link. Compiling a second copy collides at link
    // time and would ship stb's decoder twice in one binary.

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

    // `zig build test` — the conversion logic against hand-built assimp structs.
    // Kept out of the default step so the library build stays a pure compile;
    // ctest invokes this step directly.
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
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
