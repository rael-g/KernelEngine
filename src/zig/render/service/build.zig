const std = @import("std");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common    = b.option([]const u8, "ke-common-include",    "kernel_engine/common include dir")    orelse @panic("-Dke-common-include required");
    const heap_src = b.option([]const u8, "heap-src", "path to the shared Zig heap.zig") orelse @panic("-Dheap-src required");
    const ke_ecs       = b.option([]const u8, "ke-ecs-include",       "kernel_engine/ecs include dir")       orelse @panic("-Dke-ecs-include required");
    const ke_runtime   = b.option([]const u8, "ke-runtime-include",   "kernel_engine/runtime include dir")   orelse @panic("-Dke-runtime-include required");
    const ke_spatial   = b.option([]const u8, "ke-spatial-include",   "kernel_engine/spatial include dir")   orelse @panic("-Dke-spatial-include required");
    const ke_render    = b.option([]const u8, "ke-render-include",    "kernel_engine/render include dir")    orelse @panic("-Dke-render-include required");
    const ke_framework = b.option([]const u8, "ke-framework-include", "ke_framework's public include dir")   orelse @panic("-Dke-framework-include required");
    const ke_resource_cache = b.option([]const u8, "ke-resource-cache-include", "kernel_engine/resource_cache include dir") orelse @panic("-Dke-resource-cache-include required");
    const ke_text      = b.option([]const u8, "ke-text-include",      "kernel_engine/text include dir")      orelse @panic("-Dke-text-include required");
    const ke_logger    = b.option([]const u8, "ke-logger-include",    "kernel_engine/logger include dir")    orelse @panic("-Dke-logger-include required");
    const ke_self      = b.option([]const u8, "ke-self-include",      "this plugin's include dir")           orelse @panic("-Dke-self-include required");
    const ke_lib_dir   = b.option([]const u8, "ke-lib-dir",           "dir with ke_common import lib")       orelse @panic("-Dke-lib-dir required");
    const magenta_vs_wgsl = b.option([]const u8, "magenta-vs-wgsl", "generated magenta placeholder vertex WGSL path")   orelse @panic("-Dmagenta-vs-wgsl required");
    const magenta_fs_wgsl = b.option([]const u8, "magenta-fs-wgsl", "generated magenta placeholder fragment WGSL path") orelse @panic("-Dmagenta-fs-wgsl required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/render_service.zig"),
        .target    = target,
        .optimize  = optimize,
        .link_libc = true,
    });
    mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    inline for (.{ ke_common, ke_ecs, ke_runtime, ke_spatial, ke_render, ke_framework, ke_resource_cache, ke_text, ke_logger, ke_self }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.linkSystemLibrary("ke_resource_cache_default", .{});
    mod.linkSystemLibrary("ke_runtime", .{});
    mod.addCMacro("KE_RENDER_CORE_EXPORT", "");

    mod.addAnonymousImport("magenta.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = magenta_vs_wgsl } });
    mod.addAnonymousImport("magenta.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = magenta_fs_wgsl } });

    const lib = b.addLibrary(.{
        .name = "ke_render_service",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/render_service.zig"),
        .target    = target,
        .optimize  = optimize,
        .link_libc = true,
    });
    test_mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    inline for (.{ ke_common, ke_ecs, ke_runtime, ke_spatial, ke_render, ke_framework, ke_resource_cache, ke_text, ke_logger, ke_self }) |inc| {
        test_mod.addIncludePath(.{ .cwd_relative = inc });
    }
    test_mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    test_mod.linkSystemLibrary("ke_common", .{});
    test_mod.linkSystemLibrary("ke_resource_cache_default", .{});
    test_mod.linkSystemLibrary("ke_runtime", .{});
    test_mod.addCMacro("KE_RENDER_CORE_EXPORT", "");
    test_mod.addAnonymousImport("magenta.vs.wgsl", .{ .root_source_file = .{ .cwd_relative = magenta_vs_wgsl } });
    test_mod.addAnonymousImport("magenta.fs.wgsl", .{ .root_source_file = .{ .cwd_relative = magenta_fs_wgsl } });

    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    b.step("test", "Run the render service unit tests").dependOn(&run_tests.step);
}
