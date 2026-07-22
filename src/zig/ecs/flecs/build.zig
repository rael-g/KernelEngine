const std = @import("std");

// Build the ke_ecs_flecs shared library (Zig 0.16 API) — flecs as storage-only
// ECS backend. flecs is C, so this module is Zig end to end. No ke_common
// LINK — the common headers are @cImport'd for the ke_error layout only and
// errors translate at the export seam via the shared Zig kerror utility.

pub fn build(b: *std.Build) void {
    // Plain native target: pinning the abi would make Zig treat this as a cross
    // build and stop searching the host's system library paths.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_ecs = b.option([]const u8, "ke-ecs-include", "kernel_engine/ecs include dir") orelse @panic("-Dke-ecs-include required");
    const flecs_include = b.option([]const u8, "flecs-include", "flecs headers dir") orelse @panic("-Dflecs-include required");
    // The full path, not a directory + name: vcpkg decorates the debug build
    // as libflecs_staticd, so the library name is not stable across configurations.
    const flecs_lib = b.option([]const u8, "flecs-lib", "absolute path to the flecs static library") orelse @panic("-Dflecs-lib required");
    const kerror_src = b.option([]const u8, "kerror-src", "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/ecs_flecs.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_ecs, flecs_include }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addIncludePath(b.path("include"));

    mod.addObjectFile(.{ .cwd_relative = flecs_lib });

    const kerror_mod = b.createModule(.{
        .root_source_file = .{ .cwd_relative = kerror_src },
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("kerror", kerror_mod);
    mod.addCMacro("KE_ECS_FLECS_EXPORT", "");
    // flecs::flecs (CMake) is an alias for flecs::flecs_static, which carries
    // this definition on its INTERFACE_COMPILE_DEFINITIONS — it selects the
    // static (non-dllimport/dllexport) FLECS_API. CMake propagated it
    // automatically through target_link_libraries; linking the archive
    // directly here bypasses that, so it must be set explicitly.
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

    // `zig build test` — covers flecsLogHandler, the message-capture logic the
    // abort_ hook depends on. Kept out of the default step so the library
    // build stays a pure compile; ctest invokes this step directly.
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/ecs_flecs.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_ecs, flecs_include }) |inc| {
        test_mod.addIncludePath(.{ .cwd_relative = inc });
    }
    test_mod.addIncludePath(b.path("include"));
    test_mod.addObjectFile(.{ .cwd_relative = flecs_lib });
    test_mod.addImport("kerror", b.createModule(.{
        .root_source_file = .{ .cwd_relative = kerror_src },
        .target = target,
        .optimize = optimize,
    }));
    test_mod.addCMacro("KE_ECS_FLECS_EXPORT", "");
    test_mod.addCMacro("flecs_STATIC", "");

    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);

    // abort_probe — a tiny helper that forces a genuine flecs internal
    // assertion and lets it run into the real abort_ hook. Only ever run as a
    // subprocess spawned by the integration test below; see abort_probe.zig
    // for why this can't be an in-process test. Imports ecs_flecs.zig as a
    // module (its own compile, not the shared lib) to reach the test-only
    // debugTriggerRealFlecsAssertion — so it needs the same include paths,
    // flecs object file and kerror import as the library itself.
    const probe_mod = b.createModule(.{
        .root_source_file = b.path("src/abort_probe.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_ecs, flecs_include }) |inc| {
        probe_mod.addIncludePath(.{ .cwd_relative = inc });
    }
    probe_mod.addIncludePath(b.path("include"));
    probe_mod.addObjectFile(.{ .cwd_relative = flecs_lib });
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
    integration_mod.addOptions("build_options", integration_options);

    const integration_tests = b.addTest(.{ .root_module = integration_mod });
    const run_integration_tests = b.addRunArtifact(integration_tests);

    const test_step = b.step("test", "Run the ecs_flecs unit + abort-integration tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_integration_tests.step);
}
