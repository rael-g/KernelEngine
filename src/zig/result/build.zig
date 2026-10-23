const std = @import("std");
const ke_build = @import("ke_build");

/// The `result` module, for a plugin build that imports this file as `ke_result`.
pub fn result(b: *std.Build) *std.Build.Module {
    return b.dependencyFromBuildZig(@This(), .{}).module("result");
}

/// The `dll_entry` module, for a plugin build that imports this file as `ke_result`.
pub fn dllEntry(b: *std.Build) *std.Build.Module {
    return b.dependencyFromBuildZig(@This(), .{}).module("dll_entry");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("result", .{ .root_source_file = b.path("result.zig") });
    _ = b.addModule("dll_entry", .{ .root_source_file = b.path("dll_entry.zig") });

    const test_mod = b.createModule(.{
        .root_source_file = b.path("result.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addIncludePath(b.path("../../c/result"));
    test_mod.addImport("c", ke_build.cImports(b, test_mod, b.path("test/c.h")));
    const tests = b.addTest(.{ .root_module = test_mod });
    const test_step = b.step("test", "Run the result conversion tests and, on Windows, the DLL entry point test");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    if (target.result.os.tag == .windows) addDllCrtInitTest(b, target, optimize, test_step);
}

fn addDllCrtInitTest(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    test_step: *std.Build.Step,
) void {
    const dll_entry = b.createModule(.{
        .root_source_file = b.path("dll_entry.zig"),
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
        probe_mod.addImport("dll_entry", dll_entry);

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
