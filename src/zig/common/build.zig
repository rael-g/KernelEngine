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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/error.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(b.path("include"));
    mod.addCMacro("KE_COMMON_EXPORT", "");
    mod.addImport("c", cImports(b, mod, b.path("src/c.h")));

    const lib = b.addLibrary(.{
        .name = "ke_common",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const test_step = b.step("test", "Run the ke_common tests");
    if (target.result.os.tag == .windows) addDllCrtInitTest(b, target, optimize, test_step);
}

fn addDllCrtInitTest(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    test_step: *std.Build.Step,
) void {
    const kerror = b.createModule(.{
        .root_source_file = b.path("kerror.zig"),
        .target = target,
        .optimize = optimize,
    });

    const probes = [_]struct { name: []const u8, root: []const u8 }{
        .{ .name = "ke_probe_dll_fixed", .root = "test/probe_dll_fixed.zig" },
        .{ .name = "ke_probe_dll_plain", .root = "test/probe_dll_plain.zig" },
    };

    const options = b.addOptions();
    for (probes) |probe| {
        const probe_mod = b.createModule(.{
            .root_source_file = b.path(probe.root),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        });
        probe_mod.addCSourceFile(.{ .file = b.path("test/cpp_static_init_probe.cpp") });
        probe_mod.addImport("kerror", kerror);

        const probe_dll = b.addLibrary(.{
            .name = probe.name,
            .root_module = probe_mod,
            .linkage = .dynamic,
        });
        options.addOptionPath(
            if (std.mem.endsWith(u8, probe.name, "fixed")) "probe_dll_fixed" else "probe_dll_plain",
            probe_dll.getEmittedBin(),
        );
    }

    const test_mod = b.createModule(.{
        .root_source_file = b.path("test/dll_crt_init_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addOptions("build_options", options);

    const tests = b.addTest(.{ .root_module = test_mod });
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
