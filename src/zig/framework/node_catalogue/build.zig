const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("node_catalogue", .{ .root_source_file = b.path("node_catalogue.zig"), .target = target, .optimize = optimize });
    const tests_mod = b.createModule(.{ .root_source_file = b.path("node_catalogue.zig"), .target = target, .optimize = optimize });
    for ([_]*std.Build.Module{ mod, tests_mod }) |m| {
        m.addImport("abi_framework", b.dependency("abi_framework", .{}).module("abi"));
        m.addImport("abi_part", b.dependency("abi_part", .{}).module("abi"));
        m.addImport("abi_result", b.dependency("abi_result", .{}).module("abi"));
        m.addImport("result", b.dependency("ke_result", .{}).module("result"));
    }
    tests_mod.addImport("zsub", b.dependency("zsub", .{}).module("zsub"));
    const tests = b.addTest(.{ .name = "ke_node_catalogue", .root_module = tests_mod });
    b.step("test", "Run the node catalogue tests").dependOn(&b.addRunArtifact(tests).step);
    ke_build.coverage(b, "ke_node_catalogue", tests, "");
}
