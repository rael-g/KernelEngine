const std = @import("std");

// Builds this example via Zig's own C frontend. Plain C linking only C-ABI
// shared libraries (unlike the GTest suites, nothing here crosses a C++ ABI
// boundary), so there's no need to shell out to the system compiler.

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const include_dirs = b.option([]const u8, "include-dirs", "'|'-separated include directories") orelse "";
    const libs = b.option([]const u8, "libs", "'|'-separated absolute shared-library paths, in link order") orelse @panic("-Dlibs required");
    const link_m = b.option(bool, "link-m", "link libm") orelse false;

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addCSourceFile(.{ .file = b.path("main.c"), .flags = &.{} });

    var inc_it = std.mem.splitScalar(u8, include_dirs, '|');
    while (inc_it.next()) |inc| {
        if (inc.len != 0) mod.addIncludePath(.{ .cwd_relative = inc });
    }

    // Each lib gets its own rpath entry: each_lib_rpath only tracks libraries
    // linked via linkSystemLibrary/addLibraryPath, not a raw addObjectFile
    // reference to an absolute .so path (verified: no RPATH ended up in the
    // binary without this).
    var lib_it = std.mem.splitScalar(u8, libs, '|');
    while (lib_it.next()) |lib| {
        if (lib.len == 0) continue;
        mod.addObjectFile(.{ .cwd_relative = lib });
        mod.addRPath(.{ .cwd_relative = std.fs.path.dirname(lib).? });
    }

    if (link_m) mod.linkSystemLibrary("m", .{});

    const exe = b.addExecutable(.{ .name = "demo", .root_module = mod });

    const install = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = "bin" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
