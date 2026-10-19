const std = @import("std");
const ke_common_build = @import("ke_common");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common    = b.option([]const u8, "ke-common-include",    "kernel_engine/common include dir")    orelse @panic("-Dke-common-include required");
    const heap_src = b.option([]const u8, "heap-src", "path to the shared Zig heap.zig") orelse @panic("-Dheap-src required");
    const material_pass_groups_src = b.option([]const u8, "material-pass-groups-src", "path to the shared Zig material_pass_groups.zig") orelse @panic("-Dmaterial-pass-groups-src required");
    const stubs_src = b.option([]const u8, "stubs-src", "path to the shared Zig stubs.zig") orelse @panic("-Dstubs-src required");
    const ke_math = b.option([]const u8, "ke-math-include", "kernel_engine/math include dir") orelse @panic("-Dke-math-include required");
    const ke_ecs       = b.option([]const u8, "ke-ecs-include",       "kernel_engine/ecs include dir")       orelse @panic("-Dke-ecs-include required");
    const ke_runtime   = b.option([]const u8, "ke-runtime-include",   "kernel_engine/runtime include dir")   orelse @panic("-Dke-runtime-include required");
    const ke_spatial   = b.option([]const u8, "ke-spatial-include",   "kernel_engine/spatial include dir")   orelse @panic("-Dke-spatial-include required");
    const ke_render    = b.option([]const u8, "ke-render-include",    "kernel_engine/render include dir")    orelse @panic("-Dke-render-include required");
    const ke_view      = b.option([]const u8, "ke-view-include",      "kernel_engine/view include dir")      orelse @panic("-Dke-view-include required");
    const ke_self      = b.option([]const u8, "ke-self-include",      "this plugin's include dir")           orelse @panic("-Dke-self-include required");
    const object_uniforms_src = b.option([]const u8, "object-uniforms-src", "path to the shared Zig object_uniforms.zig") orelse @panic("-Dobject-uniforms-src required");
    const ke_lib_dir   = b.option([]const u8, "ke-lib-dir",           "dir with ke_common import lib")       orelse @panic("-Dke-lib-dir required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/gbuffer_module.zig"),
        .target    = target,
        .optimize  = optimize,
        .link_libc = true,
    });
    mod.addImport("object_uniforms", b.createModule(.{ .root_source_file = .{ .cwd_relative = object_uniforms_src }, .target = target, .optimize = optimize }));
    mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    mod.addImport("material_pass_groups", b.createModule(.{ .root_source_file = .{ .cwd_relative = material_pass_groups_src }, .target = target, .optimize = optimize }));
    inline for (.{ ke_common, ke_math, ke_ecs, ke_runtime, ke_spatial, ke_render, ke_view, ke_self }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.addRPathSpecial("$ORIGIN");
    mod.addCMacro("KE_RENDER_GBUFFER_EXPORT", "");

    const zmath = b.dependency("zmath", .{});
    mod.addImport("zmath", zmath.module("root"));

    mod.addImport("c", ke_common_build.cImports(b, mod, b.path("src/c.h")));
    const lib = b.addLibrary(.{
        .name = "ke_render_gbuffer",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/gbuffer_module.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("object_uniforms", b.createModule(.{ .root_source_file = .{ .cwd_relative = object_uniforms_src }, .target = target, .optimize = optimize }));
    test_mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    test_mod.addImport("material_pass_groups", b.createModule(.{ .root_source_file = .{ .cwd_relative = material_pass_groups_src }, .target = target, .optimize = optimize }));
    test_mod.addImport("stubs", b.createModule(.{ .root_source_file = .{ .cwd_relative = stubs_src }, .target = target, .optimize = optimize }));
    inline for (.{ ke_common, ke_math, ke_ecs, ke_runtime, ke_spatial, ke_render, ke_view, ke_self }) |inc| {
        test_mod.addIncludePath(.{ .cwd_relative = inc });
    }
    test_mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    test_mod.linkSystemLibrary("ke_common", .{});
    test_mod.addCMacro("KE_RENDER_GBUFFER_EXPORT", "");
    test_mod.addImport("zmath", zmath.module("root"));

    test_mod.addImport("c", ke_common_build.cImports(b, test_mod, b.path("src/c.h")));
    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    b.step("test", "Run the gbuffer pass unit tests").dependOn(&run_tests.step);
}
