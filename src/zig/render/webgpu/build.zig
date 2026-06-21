const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── wgpu-native dependency ─────────────────────────────────────────────
    // Fetched via build.zig.zon (zig fetch --save <url>).
    const webgpu_dep = b.dependency("webgpu_native", .{
        .target = target,
        .optimize = optimize,
    });

    // ── Shared library ─────────────────────────────────────────────────────
    const lib = b.addSharedLibrary(.{
        .name = "ke_gpu_device_webgpu",
        .root_source_file = b.path("src/gpu_device_webgpu.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Kernel engine C headers (common + render domain).
    lib.addIncludePath(b.path("../../../../c/common/include"));
    lib.addIncludePath(b.path("../../../../c/render/include"));

    // WebGPU header + native lib from the dependency.
    lib.addIncludePath(webgpu_dep.path("include"));
    lib.linkLibrary(webgpu_dep.artifact("wgpu_native"));

    lib.linkLibC();

    // Export macro for DLL exports on Windows.
    lib.defineCMacro("KE_GPU_WEBGPU_EXPORT", null);

    b.installArtifact(lib);

    // ── Tests ──────────────────────────────────────────────────────────────
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/gpu_device_webgpu.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.addIncludePath(b.path("../../../../c/common/include"));
    unit_tests.addIncludePath(b.path("../../../../c/render/include"));
    unit_tests.addIncludePath(webgpu_dep.path("include"));
    unit_tests.linkLibrary(webgpu_dep.artifact("wgpu_native"));
    unit_tests.linkLibC();

    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
