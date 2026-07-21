const std = @import("std");

// Build the ke_physics_2d_box2d shared library (Zig 0.16 API) — the Box2D v3
// backed 2D physics world. v3 exposes a C API, so this module is Zig end to
// end. No ke_common LINK — the common headers are @cImport'd for the ke_error
// layout only and errors translate at the export seam via the shared Zig
// kerror utility.

pub fn build(b: *std.Build) void {
    // Plain native target: pinning the abi would make Zig treat this as a cross
    // build and stop searching the host's system library paths.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_physics = b.option([]const u8, "ke-physics-include", "kernel_engine/physics include dir") orelse @panic("-Dke-physics-include required");
    const ke_logger = b.option([]const u8, "ke-logger-include", "kernel_engine/logger include dir") orelse @panic("-Dke-logger-include required");
    const box2d_include = b.option([]const u8, "box2d-include", "Box2D headers dir") orelse @panic("-Dbox2d-include required");
    // The full path, not a directory + name: vcpkg decorates the debug build
    // as libbox2dd, so the library name is not stable across configurations.
    const box2d_lib = b.option([]const u8, "box2d-lib", "absolute path to the Box2D library") orelse @panic("-Dbox2d-lib required");
    const kerror_src = b.option([]const u8, "kerror-src", "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/box2d_physics.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_physics, ke_logger, box2d_include }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addIncludePath(b.path("include"));

    mod.addObjectFile(.{ .cwd_relative = box2d_lib });

    const kerror_mod = b.createModule(.{
        .root_source_file = .{ .cwd_relative = kerror_src },
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("kerror", kerror_mod);
    mod.addCMacro("KE_PHYSICS_BOX2D_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_physics_2d_box2d",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
