const std = @import("std");

// Build the ke_render_tonemap shared library (Zig 0.16 API).
// A standalone render pass plugin: talks to the rest of the pipeline only
// through the borrowed ke_runtime/ke_render_core/ke_gpu_device handles passed
// to its factory — no link to ke_render_core's Zig sources.

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common    = b.option([]const u8, "ke-common-include",    "kernel_engine/common include dir")    orelse @panic("-Dke-common-include required");
    const ke_allocator = b.option([]const u8, "ke-allocator-include", "kernel_engine/allocator include dir") orelse @panic("-Dke-allocator-include required");
    const ke_logger  = b.option([]const u8, "ke-logger-include",  "kernel_engine/logger include dir")  orelse @panic("-Dke-logger-include required");
    const ke_runtime = b.option([]const u8, "ke-runtime-include", "kernel_engine/runtime include dir") orelse @panic("-Dke-runtime-include required");
    const ke_ecs     = b.option([]const u8, "ke-ecs-include",     "kernel_engine/ecs include dir")     orelse @panic("-Dke-ecs-include required");
    const ke_render  = b.option([]const u8, "ke-render-include",  "kernel_engine/render include dir")  orelse @panic("-Dke-render-include required");
    const ke_self    = b.option([]const u8, "ke-self-include",    "this plugin's include dir")         orelse @panic("-Dke-self-include required");
    const ke_lib_dir = b.option([]const u8, "ke-lib-dir",         "dir with ke_common import lib")     orelse @panic("-Dke-lib-dir required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/tonemap_module.zig"),
        .target    = target,
        .optimize  = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_allocator, ke_logger, ke_runtime, ke_ecs, ke_render, ke_self }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.addCMacro("KE_RENDER_TONEMAP_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_render_tonemap",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
