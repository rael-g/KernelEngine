const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("input_names", .{ .root_source_file = b.path("input_names.zig"), .target = target, .optimize = optimize });
    const tests_mod = b.createModule(.{ .root_source_file = b.path("input_names.zig"), .target = target, .optimize = optimize, .link_libc = true });
    for ([_]*std.Build.Module{ mod, tests_mod }) |m| {
        m.addImport("abi_input", b.dependency("abi_input", .{}).module("abi"));
    }
    const tests = b.addTest(.{ .name = "ke_input_names", .root_module = tests_mod });
    b.step("test", "Run the input names tests").dependOn(&b.addRunArtifact(tests).step);
    ke_build.coverage(b, "ke_input_names", tests, "");
}
