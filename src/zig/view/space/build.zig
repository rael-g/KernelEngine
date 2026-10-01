const std = @import("std");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const heap_src = b.option([]const u8, "heap-src", "path to the shared Zig heap.zig") orelse @panic("-Dheap-src required");
    const ke_render = b.option([]const u8, "ke-render-include", "kernel_engine/render include dir") orelse @panic("-Dke-render-include required");
    const ke_view   = b.option([]const u8, "ke-view-include",   "kernel_engine/view include dir")   orelse @panic("-Dke-view-include required");
    const ke_self   = b.option([]const u8, "ke-self-include",   "this plugin's include dir")        orelse @panic("-Dke-self-include required");
    const ke_lib_dir = b.option([]const u8, "ke-lib-dir",       "dir with ke_common import lib")    orelse @panic("-Dke-lib-dir required");
    const kerror_src = b.option([]const u8, "kerror-src",       "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");

    const zmath = b.dependency("zmath", .{});

    const includes = .{ ke_common, ke_render, ke_view, ke_self };

    const mod = b.createModule(.{
        .root_source_file = b.path("src/view_space.zig"),
        .target    = target,
        .optimize  = optimize,
        .link_libc = true,
    });
    mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    inline for (includes) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.addImport("zmath", zmath.module("root"));
    mod.addImport("kerror", b.createModule(.{
        .root_source_file = .{ .cwd_relative = kerror_src },
        .target = target,
        .optimize = optimize,
    }));
    mod.addCMacro("KE_VIEW_SPACE_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_view_space",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/view_space.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    inline for (includes) |inc| {
        test_mod.addIncludePath(.{ .cwd_relative = inc });
    }
    test_mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    test_mod.linkSystemLibrary("ke_common", .{});
    test_mod.addImport("zmath", zmath.module("root"));
    test_mod.addImport("kerror", b.createModule(.{
        .root_source_file = .{ .cwd_relative = kerror_src },
        .target = target,
        .optimize = optimize,
    }));
    test_mod.addCMacro("KE_VIEW_SPACE_EXPORT", "");

    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    b.step("test", "Run the view space unit tests").dependOn(&run_tests.step);
}
