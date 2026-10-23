//! The functions every plugin's `build.zig` shares.

const std = @import("std");

/// Translates `header` with the include directories and C macros `from` was given, and returns the
/// module of the result. The translation is a build step of its own, so a change to any header it
/// reads rebuilds every module importing it. Call it once `from` is fully configured.
pub fn cImports(b: *std.Build, from: *std.Build.Module, header: std.Build.LazyPath) *std.Build.Module {
    const tc = b.addTranslateC(.{
        .root_source_file = header,
        .target = from.resolved_target.?,
        .optimize = from.optimize.?,
        .link_libc = from.link_libc orelse false,
    });
    for (from.include_dirs.items) |dir| switch (dir) {
        .path => |p| tc.addIncludePath(p),
        .path_system => |p| tc.addSystemIncludePath(p),
        .path_after => |p| tc.addAfterIncludePath(p),
        .config_header_step => |h| tc.addConfigHeader(h),
        .framework_path => |p| tc.addFrameworkPath(p),
        .framework_path_system => |p| tc.addSystemFrameworkPath(p),
        .other_step, .embed_path => @panic("cImports: only include paths, config headers and frameworks are translated"),
    };
    for (from.c_macros.items) |m| tc.defineCMacroRaw(m["-D".len..]);
    return tc.createModule();
}

pub fn build(_: *std.Build) void {}
