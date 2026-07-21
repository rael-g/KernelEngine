const std = @import("std");

// Build the ke_common shared library (Zig 0.16 API) — the engine's error
// vocabulary. Pure logic: no third-party C, no vcpkg lib, and no allocator
// link (the heap-owned error copies go straight to libc malloc/free). The
// public headers under include/ stay C; only the implementation is Zig.
//
// This library exports data symbols (the KE_ERROR_* type singletons) alongside
// its functions, so C callers can keep taking their addresses.

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/error.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(b.path("include"));
    mod.addCMacro("KE_COMMON_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_common",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
