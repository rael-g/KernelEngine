const std = @import("std");

// Builds this example via Zig's own C frontend, after generating the SPIR-V
// header pair with glslangValidator — the same tool CMake invoked directly.
// See examples/c/01_minimal_log/build.zig for why plain C doesn't need the
// system-compiler dance the GTest suites do.

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const glslang = b.option([]const u8, "glslang", "path to glslangValidator") orelse "glslangValidator";
    // e.g. "triangle" turns into triangle.vert.glsl -> triangle_vert.h
    // (symbol triangle_vert_spv) and the matching .frag pair.
    const shader_name = b.option([]const u8, "shader-name", "base name shared by the .vert.glsl/.frag.glsl pair") orelse @panic("-Dshader-name required");
    const shader_out_dir = b.option([]const u8, "shader-out-dir", "directory to write generated shader headers into") orelse @panic("-Dshader-out-dir required");
    const include_dirs = b.option([]const u8, "include-dirs", "'|'-separated include directories") orelse "";
    const libs = b.option([]const u8, "libs", "'|'-separated absolute shared-library paths, in link order") orelse @panic("-Dlibs required");
    const link_m = b.option(bool, "link-m", "link libm") orelse false;

    const vert_header = b.pathJoin(&.{ shader_out_dir, b.fmt("{s}_vert.h", .{shader_name}) });
    const frag_header = b.pathJoin(&.{ shader_out_dir, b.fmt("{s}_frag.h", .{shader_name}) });

    const gen_vert = b.addSystemCommand(&.{
        glslang, "-V", "-S", "vert", "--vn", b.fmt("{s}_vert_spv", .{shader_name}),
        b.pathFromRoot(b.fmt("{s}.vert.glsl", .{shader_name})),
        "-o", vert_header,
    });
    const gen_frag = b.addSystemCommand(&.{
        glslang, "-V", "-S", "frag", "--vn", b.fmt("{s}_frag_spv", .{shader_name}),
        b.pathFromRoot(b.fmt("{s}.frag.glsl", .{shader_name})),
        "-o", frag_header,
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

    if (link_m) mod.linkSystemLibrary("m", .{});

    const exe = b.addExecutable(.{ .name = "demo", .root_module = mod });
    exe.step.dependOn(&gen_vert.step);
    exe.step.dependOn(&gen_frag.step);

    const install = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = "bin" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
