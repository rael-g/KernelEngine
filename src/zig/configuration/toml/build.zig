const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "Path to kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const heap_src = b.option([]const u8, "heap-src", "path to the shared Zig heap.zig") orelse @panic("-Dheap-src required");
    const ke_config = b.option([]const u8, "ke-config-include", "Path to kernel_engine/configuration include dir") orelse @panic("-Dke-config-include required");
    const ke_lib_dir = b.option([]const u8, "ke-lib-dir", "Dir containing ke_common import lib") orelse @panic("-Dke-lib-dir required");

    const tomlc99_dir = b.option([]const u8, "tomlc99-dir", "path to the shared vendored tomlc99 dir") orelse
        b.pathJoin(&.{ b.build_root.path.?, "..", "..", "common", "third_party", "tomlc99" });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/configuration_toml.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    addTomlc99(b, mod, tomlc99_dir);
    mod.addIncludePath(.{ .cwd_relative = ke_common });
    mod.addIncludePath(.{ .cwd_relative = ke_config });
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.addCMacro("KE_CONFIGURATION_TOML_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_configuration_toml",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/configuration_toml.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    addTomlc99(b, test_mod, tomlc99_dir);
    test_mod.addIncludePath(.{ .cwd_relative = ke_common });
    test_mod.addIncludePath(.{ .cwd_relative = ke_config });
    test_mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    test_mod.linkSystemLibrary("ke_common", .{});

    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}

pub fn addTomlc99(b: *std.Build, mod: *std.Build.Module, dir: []const u8) void {
    mod.addIncludePath(.{ .cwd_relative = dir });
    mod.addCSourceFile(.{
        .file = .{ .cwd_relative = b.pathJoin(&.{ dir, "toml.c" }) },
        .flags = &.{"-fno-sanitize=undefined"},
    });
}
