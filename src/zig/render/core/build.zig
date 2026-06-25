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
    const ke_self      = b.option([]const u8, "ke-self-include",      "this plugin's include dir")           orelse @panic("-Dke-self-include required");
    const ke_lib_dir   = b.option([]const u8, "ke-lib-dir",           "dir with ke_common import lib")       orelse @panic("-Dke-lib-dir required");
    const forward_vs_wgsl = b.option([]const u8, "forward-vs-wgsl",   "generated forward vertex WGSL path")  orelse @panic("-Dforward-vs-wgsl required");
    const forward_fs_wgsl = b.option([]const u8, "forward-fs-wgsl",   "generated forward fragment WGSL path") orelse @panic("-Dforward-fs-wgsl required");
    const skybox_vs_wgsl  = b.option([]const u8, "skybox-vs-wgsl",    "generated skybox vertex WGSL path")   orelse @panic("-Dskybox-vs-wgsl required");
    const skybox_fs_wgsl  = b.option([]const u8, "skybox-fs-wgsl",    "generated skybox fragment WGSL path") orelse @panic("-Dskybox-fs-wgsl required");
    const shadow_vs_wgsl  = b.option([]const u8, "shadow-vs-wgsl",    "generated shadow vertex WGSL path")   orelse @panic("-Dshadow-vs-wgsl required");
    const shadow_fs_wgsl  = b.option([]const u8, "shadow-fs-wgsl",    "generated shadow fragment WGSL path") orelse @panic("-Dshadow-fs-wgsl required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/render_core.zig"),
        .target    = target,
        .optimize  = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_allocator, ke_ecs, ke_runtime, ke_spatial, ke_render, ke_self }) |inc| {
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
    mod.addAnonymousImport("forward.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = forward_vs_wgsl } });
    mod.addAnonymousImport("forward.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = forward_fs_wgsl } });
    mod.addAnonymousImport("skybox.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = skybox_vs_wgsl } });
    mod.addAnonymousImport("skybox.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = skybox_fs_wgsl } });
    mod.addAnonymousImport("shadow.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = shadow_vs_wgsl } });
    mod.addAnonymousImport("shadow.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = shadow_fs_wgsl } });

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
