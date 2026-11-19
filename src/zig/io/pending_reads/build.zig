const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("pending_reads", .{ .root_source_file = b.path("pending_reads.zig"), .target = target, .optimize = optimize });
    const tests_mod = b.createModule(.{ .root_source_file = b.path("pending_reads.zig"), .target = target, .optimize = optimize, .link_libc = true });
    for ([_]*std.Build.Module{ mod, tests_mod }) |m| {
        m.addImport("abi_io", b.dependency("abi_io", .{}).module("abi"));
        m.addImport("abi_result", b.dependency("abi_result", .{}).module("abi"));
        m.addImport("result", b.dependency("ke_result", .{}).module("result"));
    }
    tests_mod.addImport("zsub", b.dependency("zsub", .{}).module("zsub"));
    const tests = b.addTest(.{ .root_module = tests_mod });
    b.step("test", "Run the pending reads tests").dependOn(&b.addRunArtifact(tests).step);
    ke_build.coverage(b, "ke_io_pending_reads", tests, b.path(""));
}
