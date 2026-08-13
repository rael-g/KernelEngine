const std = @import("std");

// Build the ke_physics_body2d shared library (Zig 0.16 API).
// The system that reconciles ke_body2d_component against a physics world. Talks
// to everything through borrowed ke_runtime/ke_ecs/ke_physics_2d handles passed
// to its factory, so it links no backend and is built against no backend's
// sources — swapping Box2D out never touches this plugin.

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common  = b.option([]const u8, "ke-common-include",  "kernel_engine/common include dir")  orelse @panic("-Dke-common-include required");
    const ke_ecs     = b.option([]const u8, "ke-ecs-include",     "kernel_engine/ecs include dir")     orelse @panic("-Dke-ecs-include required");
    const ke_logger  = b.option([]const u8, "ke-logger-include",  "kernel_engine/logger include dir")  orelse @panic("-Dke-logger-include required");
    const ke_runtime = b.option([]const u8, "ke-runtime-include", "kernel_engine/runtime include dir") orelse @panic("-Dke-runtime-include required");
    const ke_spatial = b.option([]const u8, "ke-spatial-include", "kernel_engine/spatial include dir") orelse @panic("-Dke-spatial-include required");
    const ke_physics = b.option([]const u8, "ke-physics-include", "kernel_engine/physics include dir") orelse @panic("-Dke-physics-include required");
    const ke_framework = b.option([]const u8, "ke-framework-include", "kernel_engine/framework include dir") orelse @panic("-Dke-framework-include required");
    const ke_self    = b.option([]const u8, "ke-self-include",    "this plugin's include dir")         orelse @panic("-Dke-self-include required");
    const ke_lib_dir = b.option([]const u8, "ke-lib-dir",         "dir with ke_common import lib")     orelse @panic("-Dke-lib-dir required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/body2d_module.zig"),
        .target    = target,
        .optimize  = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_ecs, ke_logger, ke_runtime, ke_spatial, ke_physics, ke_framework, ke_self }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.linkSystemLibrary("ke_runtime", .{}); // ke_system_ctx_view
    mod.addCMacro("KE_PHYSICS_BODY2D_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_physics_body2d",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
