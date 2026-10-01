const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_math = b.option([]const u8, "ke-math-include", "kernel_engine/math include dir") orelse @panic("-Dke-math-include required");
    const heap_src = b.option([]const u8, "heap-src", "path to the shared Zig heap.zig") orelse @panic("-Dheap-src required");
    const ke_ecs = b.option([]const u8, "ke-ecs-include", "kernel_engine/ecs include dir") orelse @panic("-Dke-ecs-include required");
    const ke_scheduler = b.option([]const u8, "ke-scheduler-include", "kernel_engine/scheduler include dir") orelse @panic("-Dke-scheduler-include required");
    const ke_runtime = b.option([]const u8, "ke-runtime-include", "kernel_engine/runtime include dir") orelse @panic("-Dke-runtime-include required");

    const kerror_src = b.option([]const u8, "kerror-src", "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");
    const ke_lib_dir = b.option([]const u8, "ke-lib-dir", "dir holding the built ke_ecs_flecs and ke_scheduler_enki libraries, required by the test step");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/runtime.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    inline for (.{ ke_common, ke_math, ke_ecs, ke_scheduler, ke_runtime }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    const kerror_mod = b.createModule(.{ .root_source_file = .{ .cwd_relative = kerror_src }, .target = target, .optimize = optimize });
    mod.addImport("kerror", kerror_mod);
    mod.addIncludePath(b.path("include"));
    mod.addCMacro("KE_RUNTIME_CREATE_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_runtime",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const test_step = b.step("test", "Run unit tests");
    if (ke_lib_dir) |lib_dir| {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("src/runtime.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
        inline for (.{ ke_common, ke_math, ke_ecs, ke_scheduler, ke_runtime }) |inc| {
            test_mod.addIncludePath(.{ .cwd_relative = inc });
        }
        test_mod.addImport("kerror", b.createModule(.{
            .root_source_file = .{ .cwd_relative = kerror_src },
            .target = target,
            .optimize = optimize,
        }));
        test_mod.addIncludePath(b.path("include"));
        test_mod.addCMacro("KE_RUNTIME_CREATE_EXPORT", "");
        test_mod.addLibraryPath(.{ .cwd_relative = lib_dir });
        test_mod.addRPath(.{ .cwd_relative = lib_dir });
        test_mod.linkSystemLibrary("ke_ecs_flecs", .{});
        test_mod.linkSystemLibrary("ke_scheduler_enki", .{});

        const unit_tests = b.addTest(.{ .root_module = test_mod });
        test_step.dependOn(&b.addRunArtifact(unit_tests).step);
    } else {
        test_step.dependOn(&b.addFail("-Dke-lib-dir required to run the runtime tests").step);
    }
}
