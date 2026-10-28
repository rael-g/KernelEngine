const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    ke_build.plugin(b, .{
        .name = "ke_window_glfw",
        .root = "src/window_glfw.zig",
        .abi = &.{ "abi_input", "abi_result", "abi_window", "abi_window_glfw_factory" },
        .common = &.{"heap"},
        .translations = &.{.{ .name = "c", .header = "src/c.h" }},
        .third_party = thirdParty,
        .tests = "Run the window core unit tests",
    });
}

fn thirdParty(b: *std.Build, mod: *std.Build.Module) void {
    const glfw_include = b.option([]const u8, "glfw-include", "GLFW headers dir") orelse @panic("-Dglfw-include required");
    const glfw_lib = b.option([]const u8, "glfw-lib", "dir holding the GLFW library") orelse @panic("-Dglfw-lib required");
    mod.addIncludePath(.{ .cwd_relative = glfw_include });

    mod.addLibraryPath(.{ .cwd_relative = glfw_lib });
    mod.linkSystemLibrary("glfw3", .{});

    if (mod.resolved_target.?.result.os.tag == .linux) {
        mod.linkSystemLibrary("X11", .{});
    } else if (mod.resolved_target.?.result.os.tag == .windows) {
        mod.linkSystemLibrary("gdi32", .{});
        mod.linkSystemLibrary("user32", .{});
        mod.linkSystemLibrary("shell32", .{});
        mod.linkSystemLibrary("opengl32", .{});
    }
}
