const std = @import("std");

// Build the ke_scheduler_enki shared library (Zig 0.16 API) — the enkiTS-backed
// task scheduler. Uses enkiTS's C API, so no C++ of our own; enkiTS itself is a
// C++ static library, which is why the C++ runtime is linked in. No ke_common
// LINK — the common headers are @cImport'd for the ke_error layout only and
// errors translate at the export seam via the shared Zig kerror utility.

pub fn build(b: *std.Build) void {
    // Plain native target: pinning the abi would make Zig treat this as a cross
    // build and stop searching the host paths where the C++ runtime lives.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_scheduler = b.option([]const u8, "ke-scheduler-include", "kernel_engine/scheduler include dir") orelse @panic("-Dke-scheduler-include required");
    const enki_include = b.option([]const u8, "enki-include", "enkiTS headers dir") orelse @panic("-Denki-include required");
    const enki_lib = b.option([]const u8, "enki-lib", "dir holding the enkiTS library") orelse @panic("-Denki-lib required");
    const kerror_src = b.option([]const u8, "kerror-src", "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/enki_scheduler.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        // enkiTS is built against Zig's bundled libc++; this .so must embed
        // and export the same runtime for downstream consumers.
        .link_libcpp = true,
    });
    inline for (.{ ke_common, ke_scheduler, enki_include }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addIncludePath(b.path("include"));

    mod.addLibraryPath(.{ .cwd_relative = enki_lib });
    mod.linkSystemLibrary("enkiTS", .{});

    const kerror_mod = b.createModule(.{
        .root_source_file = .{ .cwd_relative = kerror_src },
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("kerror", kerror_mod);
    mod.addCMacro("KE_SCHEDULER_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_scheduler_enki",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
