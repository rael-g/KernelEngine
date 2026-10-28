const std = @import("std");
const ke_build = @import("ke_build");
const ke_logger_build = @import("ke_logger");
const ke_result_build = @import("ke_result");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const heap_src = b.option([]const u8, "heap-src", "path to the shared Zig heap.zig") orelse @panic("-Dheap-src required");
    const box2d_include = b.option([]const u8, "box2d-include", "Box2D headers dir") orelse @panic("-Dbox2d-include required");
    const box2d_lib = b.option([]const u8, "box2d-lib", "absolute path to the Box2D library") orelse @panic("-Dbox2d-lib required");

    const lib = b.addLibrary(.{
        .name = "ke_physics_2d_box2d",
        .root_module = module(b, target, optimize, heap_src, box2d_include, box2d_lib),
        .linkage = .dynamic,
    });
    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const unit_tests = b.addTest(.{ .root_module = module(b, target, optimize, heap_src, box2d_include, box2d_lib) });
    b.step("test", "Run the Box2D physics unit tests").dependOn(&b.addRunArtifact(unit_tests).step);
}

fn module(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    heap_src: []const u8,
    box2d_include: []const u8,
    box2d_lib: []const u8,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/box2d_physics.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addImport("heap", b.createModule(.{ .root_source_file = .{ .cwd_relative = heap_src }, .target = target, .optimize = optimize }));
    mod.addIncludePath(.{ .cwd_relative = box2d_include });
    mod.addObjectFile(.{ .cwd_relative = box2d_lib });
    mod.addImport("dll_entry", ke_result_build.dllEntry(b));
    mod.addImport("box2d", ke_build.cImports(b, mod, b.path("src/box2d.h")));
    mod.addImport("log", ke_logger_build.log(b));
    mod.addImport("result", ke_result_build.result(b));
    inline for (.{ "abi_physics", "abi_result", "abi_physics_2d_box2d" }) |name| {
        mod.addImport(name, b.dependency(name, .{}).module("abi"));
    }
    return mod;
}
