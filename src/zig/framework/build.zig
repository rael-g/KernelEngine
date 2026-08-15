const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const tomlc99_dir = b.option([]const u8, "tomlc99-dir", "path to the shared vendored tomlc99 dir") orelse
        b.pathJoin(&.{ b.build_root.path.?, "..", "common", "third_party", "tomlc99" });

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_ecs = b.option([]const u8, "ke-ecs-include", "kernel_engine/ecs include dir") orelse @panic("-Dke-ecs-include required");
    const ke_spatial = b.option([]const u8, "ke-spatial-include", "kernel_engine/spatial include dir") orelse @panic("-Dke-spatial-include required");
    const ke_input = b.option([]const u8, "ke-input-include", "kernel_engine/input include dir") orelse @panic("-Dke-input-include required");
    const ke_render = b.option([]const u8, "ke-render-include", "kernel_engine/render include dir") orelse @panic("-Dke-render-include required");
    const ke_asset = b.option([]const u8, "ke-asset-include", "kernel_engine/asset include dir") orelse @panic("-Dke-asset-include required");
    const ke_text = b.option([]const u8, "ke-text-include", "kernel_engine/text include dir") orelse @panic("-Dke-text-include required");
    const ke_runtime = b.option([]const u8, "ke-runtime-include", "kernel_engine/runtime include dir") orelse @panic("-Dke-runtime-include required");
    const ke_scheduler = b.option([]const u8, "ke-scheduler-include", "kernel_engine/scheduler include dir") orelse @panic("-Dke-scheduler-include required");
    const ke_logger = b.option([]const u8, "ke-logger-include", "kernel_engine/logger include dir") orelse @panic("-Dke-logger-include required");
    const kerror_src = b.option([]const u8, "kerror-src", "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");
    const ke_lib_dir = b.option([]const u8, "ke-lib-dir", "dir holding the built ke_runtime library") orelse @panic("-Dke-lib-dir required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/framework_root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_ecs, ke_spatial, ke_input, ke_render, ke_asset, ke_text, ke_runtime, ke_scheduler, ke_logger }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addIncludePath(b.path("include"));
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_runtime", .{});
    addTomlc99(b, mod, tomlc99_dir);
    const kerror_mod = b.createModule(.{ .root_source_file = .{ .cwd_relative = kerror_src }, .target = target, .optimize = optimize });
    mod.addImport("kerror", kerror_mod);

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

    const test_step = b.step("test", "Run unit tests");
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("src/framework_root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        inline for (.{ ke_common, ke_ecs, ke_spatial, ke_input, ke_render, ke_asset, ke_text, ke_runtime, ke_scheduler, ke_logger }) |inc| {
            test_mod.addIncludePath(.{ .cwd_relative = inc });
        }
        test_mod.addIncludePath(b.path("include"));
        test_mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
        test_mod.linkSystemLibrary("ke_runtime", .{});
        addTomlc99(b, test_mod, tomlc99_dir);
        test_mod.addImport("kerror", b.createModule(.{
            .root_source_file = .{ .cwd_relative = kerror_src },
            .target = target,
            .optimize = optimize,
        }));

        const unit_tests = b.addTest(.{ .root_module = test_mod });
        test_step.dependOn(&b.addRunArtifact(unit_tests).step);
    }
}

/// Wires the shared vendored tomlc99 into `mod`: its include dir plus
/// `toml.c`, compiled with -fno-sanitize=undefined because Zig's Debug build
/// enables UBSan on the C it compiles and this third-party source carries UB
/// that is not ours to fix.
pub fn addTomlc99(b: *std.Build, mod: *std.Build.Module, dir: []const u8) void {
    mod.addIncludePath(.{ .cwd_relative = dir });
    mod.addCSourceFile(.{
        .file = .{ .cwd_relative = b.pathJoin(&.{ dir, "toml.c" }) },
        .flags = &.{"-fno-sanitize=undefined"},
    });
}
