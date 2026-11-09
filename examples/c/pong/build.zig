const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const include_dirs = b.option([]const u8, "include-dirs", "'|'-separated include directories") orelse "";
    const libs = b.option([]const u8, "libs", "'|'-separated absolute shared-library paths, in link order") orelse @panic("-Dlibs required");

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror", "-Wno-unused-command-line-argument" };
    mod.addCSourceFile(.{ .file = b.path("main.c"), .flags = flags });
    mod.addCSourceFile(.{ .file = b.path("pong.c"), .flags = flags });

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
    if (target.result.os.tag != .windows) mod.linkSystemLibrary("m", .{});

    const exe = b.addExecutable(.{ .name = "demo", .root_module = mod });
    b.getInstallStep().dependOn(&b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = "bin" } } }).step);
}
