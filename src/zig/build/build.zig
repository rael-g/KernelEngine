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

/// A module of a Zig package the plugin's `build.zig.zon` declares, and the name it is imported
/// under.
pub const Package = struct {
    name: []const u8,
    dependency: []const u8,
    module: []const u8,
};

/// What a plugin is built from. `abi`, `common`, `packages` and the shared
/// `log`, `result` and `dll_entry` modules are looked up among the dependencies the plugin's own
/// `build.zig.zon` declares, so a plugin reaches only what it declared. `third_party` declares the options of the libraries the
/// plugin wraps and adds their include paths and libraries to the library's module and the
/// tests' module, before the translations are made; what only the tests link goes to the tests'
/// module alone.
pub const Plugin = struct {
    name: []const u8,
    root: []const u8,
    abi: []const []const u8 = &.{},
    common: []const []const u8 = &.{},
    translations: []const Translation = &.{},
    packages: []const Package = &.{},
    third_party: ?*const fn (b: *std.Build, modules: Modules) void = null,
    extra_roots: []const []const u8 = &.{},
    tests: []const u8,
};

/// The modules a plugin is built from: the library's, then the tests' one followed by one per
/// extra root, which a test reaches through an artifact of its own.
pub const Modules = struct {
    lib: *std.Build.Module,
    tests: []const *std.Build.Module,

    /// Every module, the library's first.
    pub fn all(self: Modules, b: *std.Build) []const *std.Build.Module {
        const list = b.allocator.alloc(*std.Build.Module, self.tests.len + 1) catch @panic("OOM");
        list[0] = self.lib;
        @memcpy(list[1..], self.tests);
        return list;
    }
};

/// What `plugin` built: the `test` step, which a plugin with extra roots extends, and the modules
/// of those roots, in the order the description lists them.
pub const Built = struct {
    test_step: *std.Build.Step,
    extra: []const *std.Build.Module,
};

/// Builds the plugin `description` describes: its shared library, installed under `lib`, and its
/// tests, run by the `test` step. They are built from twin modules, so what `third_party` adds
/// to the tests' modules alone stays out of the library; each extra root gets a module
/// configured as the tests' one.
pub fn plugin(b: *std.Build, description: Plugin) Built {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tests = b.allocator.alloc(*std.Build.Module, description.extra_roots.len + 1) catch @panic("OOM");
    tests[0] = create(b, description.root, target, optimize);
    for (description.extra_roots, tests[1..]) |root, *mod| mod.* = create(b, root, target, optimize);
    const modules: Modules = .{ .lib = create(b, description.root, target, optimize), .tests = tests };
    if (description.third_party) |configure| configure(b, modules);
    for (modules.all(b)) |mod| {
        for (description.translations) |t| mod.addImport(t.name, cImports(b, mod, b.path(t.header)));
        for (description.abi) |name| mod.addImport(name, b.dependency(name, .{}).module("abi"));
        for (description.packages) |p| mod.addImport(p.name, b.dependency(p.dependency, .{}).module(p.module));
        inline for (.{.{ "ke_common", description.common }}) |shared| {
            if (shared[1].len > 0) {
                const package = b.dependency(shared[0], .{ .target = target, .optimize = optimize });
                for (shared[1]) |name| mod.addImport(name, package.module(name));
            }
        }
        mod.addImport("log", b.dependency("ke_logger", .{}).module("log"));
        const result = b.dependency("ke_result", .{});
        mod.addImport("result", result.module("result"));
        mod.addImport("dll_entry", result.module("dll_entry"));
    }

    const lib = b.addLibrary(.{ .name = description.name, .root_module = modules.lib, .linkage = .dynamic });
    b.getInstallStep().dependOn(&b.addInstallArtifact(lib, .{ .dest_dir = .{ .override = .{ .custom = "lib" } } }).step);
    const test_step = b.step("test", description.tests);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = tests[0] })).step);
    return .{ .test_step = test_step, .extra = tests[1..] };
}

fn create(b: *std.Build, root: []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    return b.createModule(.{ .root_source_file = b.path(root), .target = target, .optimize = optimize, .link_libc = true });
}

pub fn build(_: *std.Build) void {}
