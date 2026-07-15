const std = @import("std");

// Build the ke_logger_simple shared library (Zig 0.16 API) — a kernel built-in
// (multi-sink logger). Pure logic: no third-party C, no vcpkg lib. Allocates
// through Zig's own allocator; ke_common is consumed across a plain C-ABI DLL
// boundary (ABI-neutral), same as every migrated plugin.

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_logger = b.option([]const u8, "ke-logger-include", "kernel_engine/logger include dir") orelse @panic("-Dke-logger-include required");
    const ke_lib_dir = b.option([]const u8, "ke-lib-dir", "dir with ke_common import lib") orelse @panic("-Dke-lib-dir required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/logger_simple.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_logger }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.addCMacro("KE_LOGGER_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_logger_simple",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
