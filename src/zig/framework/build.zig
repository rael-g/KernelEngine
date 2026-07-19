const std = @import("std");

// Build the ke_framework shared library (Zig 0.16 API) — the engine's
// opinionated composition layer (world, scene tree, scene loader, asset
// resolver, input actions).
//
// Mid-migration: Zig drives the build and compiles the not-yet-ported .c
// sources into this DLL, so the C→Zig port advances one file at a time with a
// green build throughout. Nothing MSVC-built is linked *into* the module:
// tomlc99 and the allocator are vendored/available C sources that Zig compiles
// itself, and ke_common is reached across a plain C-ABI DLL boundary (the
// remaining C still calls ke_error_set; it goes away with the last .c).

const c_sources = [_][]const u8{
    "src/world.c",
    "src/asset_resolver.c",
    "src/mesh_shape.c",
    "src/scene_tree.c",
    "src/input_actions.c",
    "src/scene_loader.c",
    "third_party/tomlc99/toml.c",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_allocator = b.option([]const u8, "ke-allocator-include", "kernel_engine/allocator include dir") orelse @panic("-Dke-allocator-include required");
    const ke_ecs = b.option([]const u8, "ke-ecs-include", "kernel_engine/ecs include dir") orelse @panic("-Dke-ecs-include required");
    const ke_spatial = b.option([]const u8, "ke-spatial-include", "kernel_engine/spatial include dir") orelse @panic("-Dke-spatial-include required");
    const ke_input = b.option([]const u8, "ke-input-include", "kernel_engine/input include dir") orelse @panic("-Dke-input-include required");
    const ke_render = b.option([]const u8, "ke-render-include", "kernel_engine/render include dir") orelse @panic("-Dke-render-include required");
    const ke_asset = b.option([]const u8, "ke-asset-include", "kernel_engine/asset include dir") orelse @panic("-Dke-asset-include required");
    const ke_text = b.option([]const u8, "ke-text-include", "kernel_engine/text include dir") orelse @panic("-Dke-text-include required");
    const ke_runtime = b.option([]const u8, "ke-runtime-include", "kernel_engine/runtime include dir") orelse @panic("-Dke-runtime-include required");
    const ke_scheduler = b.option([]const u8, "ke-scheduler-include", "kernel_engine/scheduler include dir") orelse @panic("-Dke-scheduler-include required");
    const allocator_src = b.option([]const u8, "allocator-src", "path to allocator_malloc.c") orelse @panic("-Dallocator-src required");
    const kerror_src = b.option([]const u8, "kerror-src", "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");
    const ke_lib_dir = b.option([]const u8, "ke-lib-dir", "dir with ke_common import lib") orelse @panic("-Dke-lib-dir required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/framework_root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_allocator, ke_ecs, ke_spatial, ke_input, ke_render, ke_asset, ke_text, ke_runtime, ke_scheduler }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addIncludePath(b.path("include"));
    mod.addIncludePath(b.path("third_party/tomlc99"));

    // The framework's own C (awaiting translation) plus vendored tomlc99, all
    // compiled with -fno-sanitize=undefined. Zig's Debug build enables UBSan on
    // C it compiles; this pre-Zig C carries UB the MSVC build tolerated
    // silently (the same class that made stb/miniaudio trap). Suppress it while
    // the C is transitional — each file's real safety comes back when it is
    // translated to Zig; tomlc99 keeps the flag permanently (vendored, not ours).
    for (c_sources) |src| {
        mod.addCSourceFile(.{ .file = b.path(src), .flags = &.{"-fno-sanitize=undefined"} });
    }
    // ke_alloc/ke_free for the remaining C. Compiled here from source rather
    // than linked: ke_allocator_malloc is an MSVC STATIC lib, and pulling MSVC
    // objects into this GNU-ABI module is exactly the mismatch to avoid. Drops
    // out with the last .c (Zig code uses std.heap.c_allocator).
    mod.addCSourceFile(.{ .file = .{ .cwd_relative = allocator_src }, .flags = &.{} });

    const kerror_mod = b.createModule(.{ .root_source_file = .{ .cwd_relative = kerror_src }, .target = target, .optimize = optimize });
    mod.addImport("kerror", kerror_mod);

    // ke_error_set, for the C that has not moved to the kerror seam util yet.
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.addCMacro("KE_FRAMEWORK_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_framework",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
