const std = @import("std");

// Build the ke_render_core shared library (Zig 0.16 API).
// Backend-agnostic: it talks only to the ke_gpu_device / ke_ecs vtables passed
// to its factory. No webgpu/window link.

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common    = b.option([]const u8, "ke-common-include",    "kernel_engine/common include dir")    orelse @panic("-Dke-common-include required");
    const ke_allocator = b.option([]const u8, "ke-allocator-include", "kernel_engine/allocator include dir") orelse @panic("-Dke-allocator-include required");
    const ke_ecs       = b.option([]const u8, "ke-ecs-include",       "kernel_engine/ecs include dir")       orelse @panic("-Dke-ecs-include required");
    const ke_runtime   = b.option([]const u8, "ke-runtime-include",   "kernel_engine/runtime include dir")   orelse @panic("-Dke-runtime-include required");
    const ke_spatial   = b.option([]const u8, "ke-spatial-include",   "kernel_engine/spatial include dir")   orelse @panic("-Dke-spatial-include required");
    const ke_render    = b.option([]const u8, "ke-render-include",    "kernel_engine/render include dir")    orelse @panic("-Dke-render-include required");
    const ke_logger    = b.option([]const u8, "ke-logger-include",    "kernel_engine/logger include dir")    orelse @panic("-Dke-logger-include required");
    const ke_self      = b.option([]const u8, "ke-self-include",      "this plugin's include dir")           orelse @panic("-Dke-self-include required");
    const ke_lib_dir   = b.option([]const u8, "ke-lib-dir",           "dir with ke_common import lib")       orelse @panic("-Dke-lib-dir required");
    const skybox_vs_wgsl  = b.option([]const u8, "skybox-vs-wgsl",    "generated skybox vertex WGSL path")   orelse @panic("-Dskybox-vs-wgsl required");
    const skybox_fs_wgsl  = b.option([]const u8, "skybox-fs-wgsl",    "generated skybox fragment WGSL path") orelse @panic("-Dskybox-fs-wgsl required");
    const shadow_vs_wgsl  = b.option([]const u8, "shadow-vs-wgsl",    "generated shadow vertex WGSL path")   orelse @panic("-Dshadow-vs-wgsl required");
    const shadow_fs_wgsl  = b.option([]const u8, "shadow-fs-wgsl",    "generated shadow fragment WGSL path") orelse @panic("-Dshadow-fs-wgsl required");
    const cluster_cull_cs_wgsl = b.option([]const u8, "cluster-cull-cs-wgsl", "generated cluster cull compute WGSL path") orelse @panic("-Dcluster-cull-cs-wgsl required");
    const tonemap_vs_wgsl = b.option([]const u8, "tonemap-vs-wgsl", "generated tonemap vertex WGSL path")   orelse @panic("-Dtonemap-vs-wgsl required");
    const tonemap_fs_wgsl = b.option([]const u8, "tonemap-fs-wgsl", "generated tonemap fragment WGSL path") orelse @panic("-Dtonemap-fs-wgsl required");
    const ui_vs_wgsl = b.option([]const u8, "ui-vs-wgsl", "generated ui vertex WGSL path")   orelse @panic("-Dui-vs-wgsl required");
    const ui_fs_wgsl = b.option([]const u8, "ui-fs-wgsl", "generated ui fragment WGSL path") orelse @panic("-Dui-fs-wgsl required");
    const mat_test_flat_vs_wgsl = b.option([]const u8, "mat-test-flat-vs-wgsl", "generated flat-material vertex WGSL path")   orelse @panic("-Dmat-test-flat-vs-wgsl required");
    const mat_test_flat_fs_wgsl = b.option([]const u8, "mat-test-flat-fs-wgsl", "generated flat-material fragment WGSL path") orelse @panic("-Dmat-test-flat-fs-wgsl required");
    const mat_test_flat_classic_vs_wgsl = b.option([]const u8, "mat-test-flat-classic-vs-wgsl", "generated classic-forward comparison vertex WGSL path")   orelse @panic("-Dmat-test-flat-classic-vs-wgsl required");
    const mat_test_flat_classic_fs_wgsl = b.option([]const u8, "mat-test-flat-classic-fs-wgsl", "generated classic-forward comparison fragment WGSL path") orelse @panic("-Dmat-test-flat-classic-fs-wgsl required");
    const mat_test_flat_no_shadow_vs_wgsl = b.option([]const u8, "mat-test-flat-no-shadow-vs-wgsl", "generated no-shadow flat-material vertex WGSL path")   orelse @panic("-Dmat-test-flat-no-shadow-vs-wgsl required");
    const mat_test_flat_no_shadow_fs_wgsl = b.option([]const u8, "mat-test-flat-no-shadow-fs-wgsl", "generated no-shadow flat-material fragment WGSL path") orelse @panic("-Dmat-test-flat-no-shadow-fs-wgsl required");
    const mat_test_flat_no_ibl_vs_wgsl = b.option([]const u8, "mat-test-flat-no-ibl-vs-wgsl", "generated no-ibl flat-material vertex WGSL path")   orelse @panic("-Dmat-test-flat-no-ibl-vs-wgsl required");
    const mat_test_flat_no_ibl_fs_wgsl = b.option([]const u8, "mat-test-flat-no-ibl-fs-wgsl", "generated no-ibl flat-material fragment WGSL path") orelse @panic("-Dmat-test-flat-no-ibl-fs-wgsl required");
    const mat_test_flat_no_shadow_no_ibl_vs_wgsl = b.option([]const u8, "mat-test-flat-no-shadow-no-ibl-vs-wgsl", "generated no-shadow-no-ibl flat-material vertex WGSL path")   orelse @panic("-Dmat-test-flat-no-shadow-no-ibl-vs-wgsl required");
    const mat_test_flat_no_shadow_no_ibl_fs_wgsl = b.option([]const u8, "mat-test-flat-no-shadow-no-ibl-fs-wgsl", "generated no-shadow-no-ibl flat-material fragment WGSL path") orelse @panic("-Dmat-test-flat-no-shadow-no-ibl-fs-wgsl required");
    const magenta_vs_wgsl = b.option([]const u8, "magenta-vs-wgsl", "generated magenta placeholder vertex WGSL path")   orelse @panic("-Dmagenta-vs-wgsl required");
    const magenta_fs_wgsl = b.option([]const u8, "magenta-fs-wgsl", "generated magenta placeholder fragment WGSL path") orelse @panic("-Dmagenta-fs-wgsl required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/render_core.zig"),
        .target    = target,
        .optimize  = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_allocator, ke_ecs, ke_runtime, ke_spatial, ke_render, ke_logger, ke_self }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.linkSystemLibrary("ke_runtime", .{}); // ke_system_ctx_* used by the forward pass
    mod.addCMacro("KE_RENDER_CORE_EXPORT", "");

    // Matrix math for the forward pass (view-proj). The engine implements no
    // math; this Zig module brings its own via the package manager (zmath).
    const zmath = b.dependency("zmath", .{});
    mod.addImport("zmath", zmath.module("root"));

    // The forward pass shaders, compiled Slang -> WGSL by CMake (one module per
    // stage), embedded here.
    mod.addAnonymousImport("skybox.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = skybox_vs_wgsl } });
    mod.addAnonymousImport("skybox.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = skybox_fs_wgsl } });
    mod.addAnonymousImport("shadow.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = shadow_vs_wgsl } });
    mod.addAnonymousImport("shadow.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = shadow_fs_wgsl } });
    mod.addAnonymousImport("cluster_cull.cs.wgsl", .{ .root_source_file = .{ .cwd_relative = cluster_cull_cs_wgsl } });
    mod.addAnonymousImport("tonemap.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = tonemap_vs_wgsl } });
    mod.addAnonymousImport("tonemap.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = tonemap_fs_wgsl } });
    mod.addAnonymousImport("ui.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = ui_vs_wgsl } });
    mod.addAnonymousImport("ui.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = ui_fs_wgsl } });
    mod.addAnonymousImport("mat_test_flat.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = mat_test_flat_vs_wgsl } });
    mod.addAnonymousImport("mat_test_flat.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = mat_test_flat_fs_wgsl } });
    mod.addAnonymousImport("mat_test_flat_classic.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = mat_test_flat_classic_vs_wgsl } });
    mod.addAnonymousImport("mat_test_flat_classic.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = mat_test_flat_classic_fs_wgsl } });
    mod.addAnonymousImport("mat_test_flat_no_shadow.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = mat_test_flat_no_shadow_vs_wgsl } });
    mod.addAnonymousImport("mat_test_flat_no_shadow.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = mat_test_flat_no_shadow_fs_wgsl } });
    mod.addAnonymousImport("mat_test_flat_no_ibl.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = mat_test_flat_no_ibl_vs_wgsl } });
    mod.addAnonymousImport("mat_test_flat_no_ibl.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = mat_test_flat_no_ibl_fs_wgsl } });
    mod.addAnonymousImport("mat_test_flat_no_shadow_no_ibl.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = mat_test_flat_no_shadow_no_ibl_vs_wgsl } });
    mod.addAnonymousImport("mat_test_flat_no_shadow_no_ibl.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = mat_test_flat_no_shadow_no_ibl_fs_wgsl } });
    mod.addAnonymousImport("magenta.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = magenta_vs_wgsl } });
    mod.addAnonymousImport("magenta.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = magenta_fs_wgsl } });

    const lib = b.addLibrary(.{
        .name = "ke_render_core",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
