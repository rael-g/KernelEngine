const std = @import("std");

// Builds this example via Zig's own C frontend, after compiling the Slang
// shader to WGSL with scripts/compile_slang.py — the same script CMake
// invoked directly. See examples/c/01_minimal_log/build.zig for why plain C
// doesn't need the system-compiler dance the GTest suites do.

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const python = b.option([]const u8, "python", "path to the Python3 interpreter") orelse "python3";
    const compile_slang = b.option([]const u8, "compile-slang", "path to scripts/compile_slang.py") orelse @panic("-Dcompile-slang required");
    const shader_out_dir = b.option([]const u8, "shader-out-dir", "directory to write the generated shader header into") orelse @panic("-Dshader-out-dir required");
    const include_dirs = b.option([]const u8, "include-dirs", "'|'-separated include directories") orelse "";
    const libs = b.option([]const u8, "libs", "'|'-separated absolute shared-library paths, in link order") orelse @panic("-Dlibs required");

    const header = b.pathJoin(&.{ shader_out_dir, "triangle_wgsl.h" });
    const gen = b.addSystemCommand(&.{
        python, compile_slang,
        "--input",  b.pathFromRoot("triangle.slang"),
        "--output", header,
        "--name",   "triangle_wgsl",
        "--target", "wgsl",
    });

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addCSourceFile(.{ .file = b.path("main.c"), .flags = &.{} });
    mod.addIncludePath(.{ .cwd_relative = shader_out_dir });

    var inc_it = std.mem.splitScalar(u8, include_dirs, '|');
    while (inc_it.next()) |inc| {
        if (inc.len != 0) mod.addIncludePath(.{ .cwd_relative = inc });
    }

    var lib_it = std.mem.splitScalar(u8, libs, '|');
    while (lib_it.next()) |lib| {
        if (lib.len == 0) continue;
        mod.addObjectFile(.{ .cwd_relative = lib });
        mod.addRPath(.{ .cwd_relative = std.fs.path.dirname(lib).? });
    }

    const exe = b.addExecutable(.{ .name = "demo", .root_module = mod });
    exe.step.dependOn(&gen.step);

    const install = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = "bin" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
