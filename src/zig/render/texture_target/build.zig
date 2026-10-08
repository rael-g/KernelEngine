const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_render = b.option([]const u8, "ke-render-include", "kernel_engine/render include dir") orelse @panic("-Dke-render-include required");
    const heap_src = b.option([]const u8, "heap-src", "path to the shared Zig heap.zig") orelse @panic("-Dheap-src required");
    const kerror_src = b.option([]const u8, "kerror-src", "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");
    const stubs_src = b.option([]const u8, "stubs-src", "path to the shared Zig stubs.zig") orelse @panic("-Dstubs-src required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/texture_target.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_render }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addIncludePath(b.path("include"));
    mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    mod.addImport("kerror", b.createModule(.{ .root_source_file = .{ .cwd_relative = kerror_src }, .target = target, .optimize = optimize }));
    mod.addCMacro("KE_GPU_RENDER_TARGET_TEXTURE_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_gpu_render_target_texture",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/texture_target.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_render }) |inc| {
        test_mod.addIncludePath(.{ .cwd_relative = inc });
    }
    test_mod.addIncludePath(b.path("include"));
    test_mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    test_mod.addImport("kerror", b.createModule(.{ .root_source_file = .{ .cwd_relative = kerror_src }, .target = target, .optimize = optimize }));
    test_mod.addImport("stubs", b.createModule(.{ .root_source_file = .{ .cwd_relative = stubs_src }, .target = target, .optimize = optimize }));
    test_mod.addCMacro("KE_GPU_RENDER_TARGET_TEXTURE_EXPORT", "");

    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run the texture render target unit tests");
    test_step.dependOn(&run_tests.step);
}
