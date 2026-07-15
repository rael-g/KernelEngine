const std = @import("std");

// Build the ke_resource_cache_default shared library (Zig 0.16 API) — a kernel
// built-in (generic refcount + path-keyed dedup cache). Pure logic: no
// third-party C, no vcpkg lib. Allocates through Zig's own allocator;
// ke_common is consumed across a plain C-ABI DLL boundary (ABI-neutral).

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_rc = b.option([]const u8, "ke-resource-cache-include", "kernel_engine/resource_cache include dir") orelse @panic("-Dke-resource-cache-include required");
    const ke_lib_dir = b.option([]const u8, "ke-lib-dir", "dir with ke_common import lib") orelse @panic("-Dke-lib-dir required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/resource_cache.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_rc }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.linkSystemLibrary("ke_common", .{});
    mod.addCMacro("KE_RESOURCE_CACHE_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_resource_cache_default",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
