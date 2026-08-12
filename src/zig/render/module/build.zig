const std = @import("std");

// Build the ke_render_module shared library (Zig 0.16 API).
// The optional "batteries included" composition: it instantiates a render
// service plus the standard set of passes and wires them together. A host that
// wants a different set skips this library entirely and instantiates the
// service and the passes it wants directly — which is why the service links
// none of them and nothing here is reachable from the service side.

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common    = b.option([]const u8, "ke-common-include",    "kernel_engine/common include dir")    orelse @panic("-Dke-common-include required");
    const ke_ecs       = b.option([]const u8, "ke-ecs-include",       "kernel_engine/ecs include dir")       orelse @panic("-Dke-ecs-include required");
    const ke_runtime   = b.option([]const u8, "ke-runtime-include",   "kernel_engine/runtime include dir")   orelse @panic("-Dke-runtime-include required");
    const ke_spatial   = b.option([]const u8, "ke-spatial-include",   "kernel_engine/spatial include dir")   orelse @panic("-Dke-spatial-include required");
    const ke_render    = b.option([]const u8, "ke-render-include",    "kernel_engine/render include dir")    orelse @panic("-Dke-render-include required");
    const ke_framework = b.option([]const u8, "ke-framework-include", "ke_framework's public include dir")   orelse @panic("-Dke-framework-include required");
    const ke_text      = b.option([]const u8, "ke-text-include",      "kernel_engine/text include dir")      orelse @panic("-Dke-text-include required");
    const ke_logger    = b.option([]const u8, "ke-logger-include",    "kernel_engine/logger include dir")    orelse @panic("-Dke-logger-include required");
    const ke_service   = b.option([]const u8, "ke-service-include",  "ke_render_service plugin include dir") orelse @panic("-Dke-service-include required");
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

    const mod = b.createModule(.{
        .root_source_file = b.path("src/render_module.zig"),
        .target    = target,
        .optimize  = optimize,
        .link_libc = true,
    });
    inline for (.{
        ke_common, ke_ecs, ke_runtime, ke_spatial, ke_render, ke_framework, ke_text, ke_logger,
        ke_service, ke_self, ke_tonemap, ke_skybox, ke_ui, ke_gbuffer, ke_shadow, ke_cluster,
        ke_deferred_lighting, ke_forward,
    }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.linkSystemLibrary("ke_runtime", .{});
    mod.linkSystemLibrary("ke_render_service", .{});
    mod.linkSystemLibrary("ke_render_tonemap", .{});
    mod.linkSystemLibrary("ke_render_skybox", .{});
    mod.linkSystemLibrary("ke_render_ui", .{});
    mod.linkSystemLibrary("ke_render_gbuffer", .{});
    mod.linkSystemLibrary("ke_render_shadow", .{});
    mod.linkSystemLibrary("ke_render_cluster", .{});
    mod.linkSystemLibrary("ke_render_deferred_lighting", .{});
    mod.linkSystemLibrary("ke_render_forward", .{});
    mod.addCMacro("KE_RENDER_CORE_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_render_module",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
