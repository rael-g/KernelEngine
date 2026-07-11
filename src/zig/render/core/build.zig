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
    const ke_resource_cache = b.option([]const u8, "ke-resource-cache-include", "kernel_engine/resource_cache include dir") orelse @panic("-Dke-resource-cache-include required");
    const ke_logger    = b.option([]const u8, "ke-logger-include",    "kernel_engine/logger include dir")    orelse @panic("-Dke-logger-include required");
    const ke_self      = b.option([]const u8, "ke-self-include",      "this plugin's include dir")           orelse @panic("-Dke-self-include required");
    const ke_tonemap   = b.option([]const u8, "ke-tonemap-include",   "ke_render_tonemap plugin include dir") orelse @panic("-Dke-tonemap-include required");
    const ke_skybox    = b.option([]const u8, "ke-skybox-include",    "ke_render_skybox plugin include dir")  orelse @panic("-Dke-skybox-include required");
    const ke_ui        = b.option([]const u8, "ke-ui-include",       "ke_render_ui plugin include dir")      orelse @panic("-Dke-ui-include required");
    const ke_gbuffer   = b.option([]const u8, "ke-gbuffer-include",  "ke_render_gbuffer plugin include dir") orelse @panic("-Dke-gbuffer-include required");
    const ke_shadow    = b.option([]const u8, "ke-shadow-include",   "ke_render_shadow plugin include dir")  orelse @panic("-Dke-shadow-include required");
    const ke_cluster   = b.option([]const u8, "ke-cluster-include",  "ke_render_cluster plugin include dir") orelse @panic("-Dke-cluster-include required");
    const ke_deferred_lighting = b.option([]const u8, "ke-deferred-lighting-include", "ke_render_deferred_lighting plugin include dir") orelse @panic("-Dke-deferred-lighting-include required");
    const ke_forward   = b.option([]const u8, "ke-forward-include",    "ke_render_forward plugin include dir") orelse @panic("-Dke-forward-include required");
    const ke_lib_dir   = b.option([]const u8, "ke-lib-dir",           "dir with ke_common import lib")       orelse @panic("-Dke-lib-dir required");
    const magenta_vs_wgsl = b.option([]const u8, "magenta-vs-wgsl", "generated magenta placeholder vertex WGSL path")   orelse @panic("-Dmagenta-vs-wgsl required");
    const magenta_fs_wgsl = b.option([]const u8, "magenta-fs-wgsl", "generated magenta placeholder fragment WGSL path") orelse @panic("-Dmagenta-fs-wgsl required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/render_core.zig"),
        .target    = target,
        .optimize  = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_allocator, ke_ecs, ke_runtime, ke_spatial, ke_render, ke_resource_cache, ke_logger, ke_self, ke_tonemap, ke_skybox, ke_ui, ke_gbuffer, ke_shadow, ke_cluster, ke_deferred_lighting, ke_forward }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.linkSystemLibrary("ke_resource_cache_default", .{}); // refcount + path-keyed dedup for mesh/texture/material
    mod.linkSystemLibrary("ke_runtime", .{}); // ke_system_ctx_* used by the forward pass
    mod.linkSystemLibrary("ke_render_tonemap", .{}); // the tonemap pass plugin
    mod.linkSystemLibrary("ke_render_skybox", .{}); // the skybox pass plugin
    mod.linkSystemLibrary("ke_render_ui", .{}); // the ui overlay pass plugin
    mod.linkSystemLibrary("ke_render_gbuffer", .{}); // the gbuffer encode pass plugin
    mod.linkSystemLibrary("ke_render_shadow", .{}); // the shadow-depth pass plugin
    mod.linkSystemLibrary("ke_render_cluster", .{}); // the clustered-light-cull pass plugin
    mod.linkSystemLibrary("ke_render_deferred_lighting", .{}); // the deferred-lighting pass plugin
    mod.linkSystemLibrary("ke_render_forward", .{}); // the transparent-forward pass plugin
    mod.addCMacro("KE_RENDER_CORE_EXPORT", "");

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
