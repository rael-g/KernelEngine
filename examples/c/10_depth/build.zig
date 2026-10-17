const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const slangc = b.option([]const u8, "slangc", "path to the fetched slangc executable") orelse @panic("-Dslangc required");
    const shader_name = b.option([]const u8, "shader-name", "base name of the .slang file holding vs_main and fs_main") orelse @panic("-Dshader-name required");
    const include_dirs = b.option([]const u8, "include-dirs", "'|'-separated include directories") orelse "";
    const libs = b.option([]const u8, "libs", "'|'-separated absolute shared-library paths, in link order") orelse @panic("-Dlibs required");
    const link_m = b.option(bool, "link-m", "link libm") orelse false;

    const source = b.pathFromRoot(b.fmt("{s}.slang", .{shader_name}));
    const gen_vert = b.addSystemCommand(&.{ slangc, source, "-target", "wgsl", "-entry", "vs_main", "-stage", "vertex", "-o" });
    const vert_wgsl = gen_vert.addOutputFileArg(b.fmt("{s}_vs.wgsl", .{shader_name}));
    const gen_frag = b.addSystemCommand(&.{ slangc, source, "-target", "wgsl", "-entry", "fs_main", "-stage", "fragment", "-o" });
    const frag_wgsl = gen_frag.addOutputFileArg(b.fmt("{s}_fs.wgsl", .{shader_name}));

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addCSourceFile(.{ .file = b.path("main.c"), .flags = &.{ "-std=gnu23", "-Wall", "-Wextra", "-Werror", "-Wno-unused-command-line-argument" } });
    mod.addEmbedPath(vert_wgsl.dirname());
    mod.addEmbedPath(frag_wgsl.dirname());

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
    mod.addRPathSpecial("$ORIGIN/../lib");

    if (link_m) mod.linkSystemLibrary("m", .{});

    const exe = b.addExecutable(.{ .name = "demo", .root_module = mod });

    const install = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = "bin" } },
    });
    b.getInstallStep().dependOn(&install.step);
}
