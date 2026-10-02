const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const compile_slang = b.option([]const u8, "compile-slang", "path to the built compile_slang.dll") orelse @panic("-Dcompile-slang required");
    const slangc = b.option([]const u8, "slangc", "path to the fetched slangc executable") orelse @panic("-Dslangc required");
    const shader_name = b.option([]const u8, "shader-name", "base name of the .slang file holding vs_main and fs_main") orelse @panic("-Dshader-name required");
    const shader_out_dir = b.option([]const u8, "shader-out-dir", "directory to write generated shader headers into") orelse @panic("-Dshader-out-dir required");
    const include_dirs = b.option([]const u8, "include-dirs", "'|'-separated include directories") orelse "";
    const libs = b.option([]const u8, "libs", "'|'-separated absolute shared-library paths, in link order") orelse @panic("-Dlibs required");
    const link_m = b.option(bool, "link-m", "link libm") orelse false;

    const vert_header = b.pathJoin(&.{ shader_out_dir, b.fmt("{s}_vs_wgsl.h", .{shader_name}) });
    const frag_header = b.pathJoin(&.{ shader_out_dir, b.fmt("{s}_fs_wgsl.h", .{shader_name}) });

    const gen_vert = b.addSystemCommand(&.{
        "dotnet",   compile_slang,
        "--slangc", slangc,                                         "--input",
        b.pathFromRoot(b.fmt("{s}.slang", .{shader_name})),         "--output",
        vert_header, "--name",                                      b.fmt("{s}_vs_wgsl", .{shader_name}),
        "--target", "wgsl",                                         "--entry",
        "vs_main",  "--stage",                                      "vertex",
    });
    const gen_frag = b.addSystemCommand(&.{
        "dotnet",   compile_slang,
        "--slangc", slangc,                                         "--input",
        b.pathFromRoot(b.fmt("{s}.slang", .{shader_name})),         "--output",
        frag_header, "--name",                                      b.fmt("{s}_fs_wgsl", .{shader_name}),
        "--target", "wgsl",                                         "--entry",
        "fs_main",  "--stage",                                      "fragment",
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
