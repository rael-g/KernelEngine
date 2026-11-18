const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("settings_schema", .{ .root_source_file = b.path("settings_schema.zig"), .target = target, .optimize = optimize });
    const tests_mod = b.createModule(.{ .root_source_file = b.path("settings_schema.zig"), .target = target, .optimize = optimize });
    for ([_]*std.Build.Module{ mod, tests_mod }) |m| {
        m.addImport("abi_settings", b.dependency("abi_settings", .{}).module("abi"));
        m.addImport("abi_result", b.dependency("abi_result", .{}).module("abi"));
        m.addImport("result", b.dependency("ke_result", .{}).module("result"));
    }
    const tests = b.addTest(.{ .root_module = tests_mod });
    b.step("test", "Run the settings schema tests").dependOn(&b.addRunArtifact(tests).step);
}
