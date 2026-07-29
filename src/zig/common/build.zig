const std = @import("std");

// Build the ke_common shared library (Zig 0.16 API) — the engine's error
// vocabulary. Pure logic: no third-party C, no vcpkg lib, and no allocator
// link (the heap-owned error copies go straight to libc malloc/free). The
// public headers under include/ stay C; only the implementation is Zig.
//
// This library exports data symbols (the KE_ERROR_* type singletons) alongside
// its functions, so C callers can keep taking their addresses.

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

    const lib = b.addLibrary(.{
        .name = "ke_common",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    // `zig build test` — guards the Windows DLL entry-point workaround this
    // module owns (see kerror.zig's `_DllMainCRTStartup`). Kept out of the
    // default step so the library build stays a pure compile.
    const test_step = b.step("test", "Run the ke_common tests");
    if (target.result.os.tag == .windows) addDllCrtInitTest(b, target, optimize, test_step);
}

/// Builds the two probe DLLs the CRT-init test compares — identical but for
/// the `_DllMainCRTStartup` re-export — and threads their paths into the test
/// through build options. Both link the same C++ translation unit, whose global
/// constructor is what the test is really observing.
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
