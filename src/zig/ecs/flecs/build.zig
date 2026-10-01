const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const heap_src = b.option([]const u8, "heap-src", "path to the shared Zig heap.zig") orelse @panic("-Dheap-src required");
    const ke_ecs = b.option([]const u8, "ke-ecs-include", "kernel_engine/ecs include dir") orelse @panic("-Dke-ecs-include required");
    const flecs_include = b.option([]const u8, "flecs-include", "flecs headers dir") orelse @panic("-Dflecs-include required");
    const flecs_lib = b.option([]const u8, "flecs-lib", "absolute path to the flecs static library") orelse @panic("-Dflecs-lib required");
    const kerror_src = b.option([]const u8, "kerror-src", "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/ecs_flecs.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    inline for (.{ ke_common, ke_ecs, flecs_include }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addIncludePath(b.path("include"));

    mod.addObjectFile(.{ .cwd_relative = flecs_lib });

    if (target.result.os.tag == .windows) {
        mod.linkSystemLibrary("ws2_32", .{});
        mod.linkSystemLibrary("dbghelp", .{});
    }

    const kerror_mod = b.createModule(.{
        .root_source_file = .{ .cwd_relative = kerror_src },
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("kerror", kerror_mod);
    mod.addCMacro("KE_ECS_FLECS_EXPORT", "");
    mod.addCMacro("flecs_STATIC", "");

    const lib = b.addLibrary(.{
        .name = "ke_ecs_flecs",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/ecs_flecs.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    inline for (.{ ke_common, ke_ecs, flecs_include }) |inc| {
        test_mod.addIncludePath(.{ .cwd_relative = inc });
    }
    test_mod.addIncludePath(b.path("include"));
    test_mod.addObjectFile(.{ .cwd_relative = flecs_lib });
    if (target.result.os.tag == .windows) {
        test_mod.linkSystemLibrary("ws2_32", .{});
        test_mod.linkSystemLibrary("dbghelp", .{});
    }
    test_mod.addImport("kerror", b.createModule(.{
        .root_source_file = .{ .cwd_relative = kerror_src },
        .target = target,
        .optimize = optimize,
    }));
    test_mod.addCMacro("KE_ECS_FLECS_EXPORT", "");
    test_mod.addCMacro("flecs_STATIC", "");

    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);

    const probe_mod = b.createModule(.{
        .root_source_file = b.path("src/abort_probe.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    probe_mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    inline for (.{ ke_common, ke_ecs, flecs_include }) |inc| {
        probe_mod.addIncludePath(.{ .cwd_relative = inc });
    }
    probe_mod.addIncludePath(b.path("include"));
    probe_mod.addObjectFile(.{ .cwd_relative = flecs_lib });
    if (target.result.os.tag == .windows) {
        probe_mod.linkSystemLibrary("ws2_32", .{});
        probe_mod.linkSystemLibrary("dbghelp", .{});
    }
    probe_mod.addImport("kerror", b.createModule(.{
        .root_source_file = .{ .cwd_relative = kerror_src },
        .target = target,
        .optimize = optimize,
    }));
    probe_mod.addCMacro("KE_ECS_FLECS_EXPORT", "");
    probe_mod.addCMacro("flecs_STATIC", "");

    const probe_exe = b.addExecutable(.{
        .name = "ecs_flecs_abort_probe",
        .root_module = probe_mod,
    });

    const integration_options = b.addOptions();
    integration_options.addOptionPath("probe_exe_path", probe_exe.getEmittedBin());

    const integration_mod = b.createModule(.{
        .root_source_file = b.path("src/abort_integration_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    integration_mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    integration_mod.addOptions("build_options", integration_options);

    const integration_tests = b.addTest(.{ .root_module = integration_mod });
    const run_integration_tests = b.addRunArtifact(integration_tests);

    const test_step = b.step("test", "Run the ecs_flecs unit + abort-integration tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_integration_tests.step);
}
