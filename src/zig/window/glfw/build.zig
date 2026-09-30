const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ke_common = b.option([]const u8, "ke-common-include", "kernel_engine/common include dir") orelse @panic("-Dke-common-include required");
    const ke_window = b.option([]const u8, "ke-window-include", "kernel_engine/window include dir") orelse @panic("-Dke-window-include required");
    const ke_input = b.option([]const u8, "ke-input-include", "kernel_engine/input include dir") orelse @panic("-Dke-input-include required");
    const ke_logger = b.option([]const u8, "ke-logger-include", "kernel_engine/logger include dir") orelse @panic("-Dke-logger-include required");
    const glfw_include = b.option([]const u8, "glfw-include", "GLFW headers dir") orelse @panic("-Dglfw-include required");
    const glfw_lib = b.option([]const u8, "glfw-lib", "dir holding the GLFW library") orelse @panic("-Dglfw-lib required");
    const kerror_src = b.option([]const u8, "kerror-src", "path to the shared Zig kerror.zig") orelse @panic("-Dkerror-src required");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/window_glfw.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_window, ke_input, ke_logger, glfw_include }) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
    }
    mod.addIncludePath(b.path("include"));

    mod.addLibraryPath(.{ .cwd_relative = glfw_lib });
    mod.linkSystemLibrary("glfw3", .{});

    if (target.result.os.tag == .linux) {
        mod.linkSystemLibrary("X11", .{});
    } else if (target.result.os.tag == .windows) {
        mod.linkSystemLibrary("gdi32", .{});
        mod.linkSystemLibrary("user32", .{});
        mod.linkSystemLibrary("shell32", .{});
        mod.linkSystemLibrary("opengl32", .{});
    }

    const kerror_mod = b.createModule(.{
        .root_source_file = .{ .cwd_relative = kerror_src },
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("kerror", kerror_mod);
    mod.addCMacro("KE_WINDOW_EXPORT", "");

    const lib = b.addLibrary(.{
        .name = "ke_window_glfw",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });
    b.getInstallStep().dependOn(&install.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    inline for (.{ ke_common, ke_window, ke_input, ke_logger, glfw_include }) |inc| {
        test_mod.addIncludePath(.{ .cwd_relative = inc });
    }
    test_mod.addIncludePath(b.path("include"));
    test_mod.addLibraryPath(.{ .cwd_relative = glfw_lib });
    test_mod.linkSystemLibrary("glfw3", .{});
    if (target.result.os.tag == .linux) {
        test_mod.linkSystemLibrary("X11", .{});
    } else if (target.result.os.tag == .windows) {
        test_mod.linkSystemLibrary("gdi32", .{});
        test_mod.linkSystemLibrary("user32", .{});
        test_mod.linkSystemLibrary("shell32", .{});
        test_mod.linkSystemLibrary("opengl32", .{});
    }
    test_mod.addImport("kerror", b.createModule(.{
        .root_source_file = .{ .cwd_relative = kerror_src },
        .target = target,
        .optimize = optimize,
    }));
    test_mod.addCMacro("KE_WINDOW_EXPORT", "");

    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    b.step("test", "Run the window core unit tests").dependOn(&run_tests.step);
}
