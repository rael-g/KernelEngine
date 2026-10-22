const std = @import("std");

/// The `log` module, for a plugin build that imports this file as `ke_logger`: the plugin root
/// names its library with `@import("log").Destination` in its `std_options`.
pub fn log(b: *std.Build) *std.Build.Module {
    return b.dependencyFromBuildZig(@This(), .{}).module("log");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("log", .{ .root_source_file = b.path("log.zig") });

    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("log.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    b.step("test", "Run the log destination tests").dependOn(&b.addRunArtifact(tests).step);
}
