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

/// A C header a plugin translates, and the name its translation is imported under.
pub const Translation = struct {
    name: []const u8,
    header: []const u8,
};

/// What a plugin is built from. `abi`, `common` and the shared `log`, `result` and `dll_entry`
/// modules are looked up among the dependencies the plugin's own `build.zig.zon` declares, so a
/// plugin reaches only what it declared. `third_party` adds the include paths, libraries and
/// options of the libraries the plugin wraps, before the translations are made.
pub const Plugin = struct {
    name: []const u8,
    root: []const u8,
    abi: []const []const u8 = &.{},
    common: []const []const u8 = &.{},
    translations: []const Translation = &.{},
    third_party: ?*const fn (*std.Build, *std.Build.Module) void = null,
    tests: []const u8,
};

/// Builds the plugin `description` describes: its shared library, installed under `lib`, and its
/// tests, run by the `test` step, from one module.
pub fn plugin(b: *std.Build, description: Plugin) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path(description.root),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    if (description.third_party) |configure| configure(b, mod);
    for (description.translations) |t| mod.addImport(t.name, cImports(b, mod, b.path(t.header)));
    for (description.abi) |name| mod.addImport(name, b.dependency(name, .{}).module("abi"));
    const common = b.dependency("ke_common", .{ .target = target, .optimize = optimize });
    for (description.common) |name| mod.addImport(name, common.module(name));
    mod.addImport("log", b.dependency("ke_logger", .{}).module("log"));
    const result = b.dependency("ke_result", .{});
    mod.addImport("result", result.module("result"));
    mod.addImport("dll_entry", result.module("dll_entry"));

    const lib = b.addLibrary(.{ .name = description.name, .root_module = mod, .linkage = .dynamic });
    b.getInstallStep().dependOn(&b.addInstallArtifact(lib, .{ .dest_dir = .{ .override = .{ .custom = "lib" } } }).step);
    b.step("test", description.tests).dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = mod })).step);
}

pub fn build(_: *std.Build) void {}
