const std = @import("std");

// Build the ke_configuration shared library (Zig 0.16 API).
//
// Through CMake the include/lib paths are passed automatically. For standalone
// builds (and `zig build test`):
//
//   zig build \
//     -Dke-common-include=/path/to/src/zig/common/include \
//     -Dke-config-include=/path/to/src/c/configuration \
//     -Dke-lib-dir=/path/to/dir/with/ke_common/import/lib

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "Path to kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_config = b.option([]const u8, "ke-config-include", "Path to kernel_engine/configuration include dir") orelse @panic("-Dke-config-include required");
    const ke_lib_dir = b.option([]const u8, "ke-lib-dir", "Dir containing ke_common import lib") orelse @panic("-Dke-lib-dir required");

    // ── Shared library ─────────────────────────────────────────────────────
    const mod = b.createModule(.{
        .root_source_file = b.path("src/configuration.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(.{ .cwd_relative = ke_common });
    mod.addIncludePath(.{ .cwd_relative = ke_config });
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.addCMacro("KE_CONFIGURATION_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_configuration",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    // ── Tests ──────────────────────────────────────────────────────────────
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/configuration.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addIncludePath(.{ .cwd_relative = ke_common });
    test_mod.addIncludePath(.{ .cwd_relative = ke_config });
    test_mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    test_mod.linkSystemLibrary("ke_common", .{});

    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
