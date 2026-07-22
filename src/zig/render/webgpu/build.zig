const std = @import("std");

// Build the ke_gpu_device_webgpu shared library (Zig 0.16 API).
//
// When building through CMake the paths are passed automatically via
// FetchContent (eliemichel/WebGPU-distribution). For standalone builds:
//
//   zig build \
//     -Dke-common-include=/path/to/src/c/common/include \
//     -Dke-render-include=/path/to/src/c/render/include \
//     -Dwgpu-include=/path/to/wgpu-native-release/include \
//     -Dwgpu-lib=/path/to/wgpu-native-release/lib

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common  = b.option([]const u8, "ke-common-include", "Path to kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_lib_dir = b.option([]const u8, "ke-lib-dir",        "Dir containing ke_common import lib")      orelse @panic("-Dke-lib-dir required");
    const ke_render  = b.option([]const u8, "ke-render-include", "Path to kernel_engine/render include dir") orelse @panic("-Dke-render-include required");
    const ke_window  = b.option([]const u8, "ke-window-include", "Path to kernel_engine/window include dir") orelse @panic("-Dke-window-include required");
    const ke_sched   = b.option([]const u8, "ke-scheduler-include", "Path to kernel_engine/scheduler include dir") orelse @panic("-Dke-scheduler-include required");
    const wgpu_inc   = b.option([]const u8, "wgpu-include",      "Path containing webgpu/webgpu.h")          orelse @panic("-Dwgpu-include required");
    const wgpu_lib   = b.option([]const u8, "wgpu-lib",          "Path containing wgpu_native DLL/lib")      orelse @panic("-Dwgpu-lib required");

    // ── Shared library ─────────────────────────────────────────────────────
    const mod = b.createModule(.{
        .root_source_file = b.path("src/gpu_device_webgpu.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    mod.addIncludePath(.{ .cwd_relative = ke_common });
    mod.addIncludePath(.{ .cwd_relative = ke_render });
    mod.addIncludePath(.{ .cwd_relative = ke_window });
    mod.addIncludePath(.{ .cwd_relative = ke_sched });
    mod.addIncludePath(.{ .cwd_relative = wgpu_inc });
    mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    mod.addLibraryPath(.{ .cwd_relative = wgpu_lib });
    mod.linkSystemLibrary("ke_common", .{});
    mod.linkSystemLibrary("wgpu_native", .{});
    // The Xlib surface path opens the display itself, so Xlib is a direct
    // dependency of this module rather than something wgpu-native provides.
    if (target.result.os.tag == .linux) {
        mod.linkSystemLibrary("X11", .{});
    }
    mod.addCMacro("KE_GPU_WEBGPU_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_gpu_device_webgpu",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    // ── Tests ──────────────────────────────────────────────────────────────
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/gpu_device_webgpu.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addIncludePath(.{ .cwd_relative = ke_common });
    test_mod.addIncludePath(.{ .cwd_relative = ke_render });
    test_mod.addIncludePath(.{ .cwd_relative = ke_window });
    test_mod.addIncludePath(.{ .cwd_relative = ke_sched });
    test_mod.addIncludePath(.{ .cwd_relative = wgpu_inc });
    test_mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
    test_mod.addLibraryPath(.{ .cwd_relative = wgpu_lib });
    test_mod.linkSystemLibrary("ke_common", .{});
    test_mod.linkSystemLibrary("wgpu_native", .{});
    if (target.result.os.tag == .linux) {
        test_mod.linkSystemLibrary("X11", .{});
    }

    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
