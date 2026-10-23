const std = @import("std");
const ke_build = @import("ke_build");
const ke_logger_build = @import("ke_logger");
const ke_result_build = @import("ke_result");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .gnu } });
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_result = b.option([]const u8, "ke-result-include", "kernel_engine/result include dir") orelse @panic("-Dke-result-include required");
    const heap_src = b.option([]const u8, "heap-src", "path to the shared Zig heap.zig") orelse @panic("-Dheap-src required");
    const ke_input = b.option([]const u8, "ke-input-include", "kernel_engine/input include dir") orelse @panic("-Dke-input-include required");



    const mod = b.createModule(.{
        .root_source_file = b.path("src/input_default.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    inline for (.{ ke_common, ke_result, ke_input }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addIncludePath(b.path("include"));
    mod.addCMacro("KE_INPUT_DEFAULT_EXPORT", "");

    mod.addImport("c", ke_build.cImports(b, mod, b.path("src/c.h")));
    mod.addImport("log", ke_logger_build.log(b));
    mod.addImport("result", ke_result_build.result(b));
    const lib = b.addLibrary(.{
        .name = "ke_input_default",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/input_default.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    inline for (.{ ke_common, ke_result, ke_input }) |inc| {
        test_mod.addIncludePath(.{ .cwd_relative = inc });
    }
    test_mod.addIncludePath(b.path("include"));
    test_mod.addCMacro("KE_INPUT_DEFAULT_EXPORT", "");

    test_mod.addImport("c", ke_build.cImports(b, test_mod, b.path("src/c.h")));
    test_mod.addImport("log", ke_logger_build.log(b));
    test_mod.addImport("result", ke_result_build.result(b));
    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    b.step("test", "Run the default input unit tests").dependOn(&run_tests.step);
}
