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
    const ke_tonemap   = b.option([]const u8, "ke-tonemap-include",   "ke_render_tonemap plugin include dir") orelse @panic("-Dke-tonemap-include required");
    const ke_skybox    = b.option([]const u8, "ke-skybox-include",    "ke_render_skybox plugin include dir")  orelse @panic("-Dke-skybox-include required");
    const ke_ui        = b.option([]const u8, "ke-ui-include",       "ke_render_ui plugin include dir")      orelse @panic("-Dke-ui-include required");
    const ke_lib_dir   = b.option([]const u8, "ke-lib-dir",           "dir with ke_common import lib")       orelse @panic("-Dke-lib-dir required");
    const shadow_vs_wgsl  = b.option([]const u8, "shadow-vs-wgsl",    "generated shadow vertex WGSL path")   orelse @panic("-Dshadow-vs-wgsl required");
    const shadow_fs_wgsl  = b.option([]const u8, "shadow-fs-wgsl",    "generated shadow fragment WGSL path") orelse @panic("-Dshadow-fs-wgsl required");
    const cluster_cull_cs_wgsl = b.option([]const u8, "cluster-cull-cs-wgsl", "generated cluster cull compute WGSL path") orelse @panic("-Dcluster-cull-cs-wgsl required");
    const mat_test_flat_gbuffer_vs_wgsl = b.option([]const u8, "mat-test-flat-gbuffer-vs-wgsl", "generated flat-material gbuffer vertex WGSL path")   orelse @panic("-Dmat-test-flat-gbuffer-vs-wgsl required");
    const mat_test_flat_gbuffer_fs_wgsl = b.option([]const u8, "mat-test-flat-gbuffer-fs-wgsl", "generated flat-material gbuffer fragment WGSL path") orelse @panic("-Dmat-test-flat-gbuffer-fs-wgsl required");
    const mat_test_flat_transparent_vs_wgsl = b.option([]const u8, "mat-test-flat-transparent-vs-wgsl", "generated flat-material transparent-forward vertex WGSL path")   orelse @panic("-Dmat-test-flat-transparent-vs-wgsl required");
    const mat_test_flat_transparent_fs_wgsl = b.option([]const u8, "mat-test-flat-transparent-fs-wgsl", "generated flat-material transparent-forward fragment WGSL path") orelse @panic("-Dmat-test-flat-transparent-fs-wgsl required");
    const deferred_lighting_vs_wgsl = b.option([]const u8, "deferred-lighting-vs-wgsl", "generated deferred-lighting vertex WGSL path")   orelse @panic("-Ddeferred-lighting-vs-wgsl required");
    const deferred_lighting_fs_wgsl = b.option([]const u8, "deferred-lighting-fs-wgsl", "generated deferred-lighting fragment WGSL path") orelse @panic("-Ddeferred-lighting-fs-wgsl required");
    const magenta_vs_wgsl = b.option([]const u8, "magenta-vs-wgsl", "generated magenta placeholder vertex WGSL path")   orelse @panic("-Dmagenta-vs-wgsl required");
    const magenta_fs_wgsl = b.option([]const u8, "magenta-fs-wgsl", "generated magenta placeholder fragment WGSL path") orelse @panic("-Dmagenta-fs-wgsl required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/render_core.zig"),
        .target    = target,
        .optimize  = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_allocator, ke_ecs, ke_runtime, ke_spatial, ke_render, ke_logger, ke_self, ke_tonemap, ke_skybox, ke_ui }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.linkSystemLibrary("ke_runtime", .{}); // ke_system_ctx_* used by the forward pass
    mod.linkSystemLibrary("ke_render_tonemap", .{}); // the tonemap pass plugin
    mod.linkSystemLibrary("ke_render_skybox", .{}); // the skybox pass plugin
    mod.linkSystemLibrary("ke_render_ui", .{}); // the ui overlay pass plugin
    mod.addCMacro("KE_RENDER_CORE_EXPORT", "");

    // Matrix math for the forward pass (view-proj). The engine implements no
    // math; this Zig module brings its own via the package manager (zmath).
    const zmath = b.dependency("zmath", .{});
    mod.addImport("zmath", zmath.module("root"));

    // The forward pass shaders, compiled Slang -> WGSL by CMake (one module per
    // stage), embedded here.
    mod.addAnonymousImport("shadow.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = shadow_vs_wgsl } });
    mod.addAnonymousImport("shadow.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = shadow_fs_wgsl } });
    mod.addAnonymousImport("cluster_cull.cs.wgsl", .{ .root_source_file = .{ .cwd_relative = cluster_cull_cs_wgsl } });
    mod.addAnonymousImport("mat_test_flat_gbuffer.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = mat_test_flat_gbuffer_vs_wgsl } });
    mod.addAnonymousImport("mat_test_flat_gbuffer.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = mat_test_flat_gbuffer_fs_wgsl } });
    mod.addAnonymousImport("mat_test_flat_transparent.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = mat_test_flat_transparent_vs_wgsl } });
    mod.addAnonymousImport("mat_test_flat_transparent.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = mat_test_flat_transparent_fs_wgsl } });
    mod.addAnonymousImport("deferred_lighting.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = deferred_lighting_vs_wgsl } });
    mod.addAnonymousImport("deferred_lighting.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = deferred_lighting_fs_wgsl } });
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
