const std = @import("std");

// Build the ke_logger_simple shared library (Zig 0.16 API) — a kernel built-in
// (multi-sink logger). Pure logic: no third-party C, no vcpkg lib, and no
// ke_common LINK — the common headers are @cImport'd for the ke_error struct
// layout only; errors are translated to the C ABI at the export seam by the
// shared Zig kerror utility. Allocates through Zig's own allocator.

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_logger = b.option([]const u8, "ke-logger-include", "kernel_engine/logger include dir") orelse @panic("-Dke-logger-include required");
    const kerror_src = b.option([]const u8, "kerror-src", "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/logger_simple.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_logger }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    const kerror_mod = b.createModule(.{
        .root_source_file = .{ .cwd_relative = kerror_src },
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("kerror", kerror_mod);
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
