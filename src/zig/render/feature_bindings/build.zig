const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("feature_bindings", .{ .root_source_file = b.path("feature_bindings.zig"), .target = target, .optimize = optimize });
    mod.addImport("abi_asset_resolver", b.dependency("abi_asset_resolver", .{}).module("abi"));
    mod.addImport("abi_render_gpu", b.dependency("abi_render_gpu", .{}).module("abi"));
    mod.addImport("abi_render", b.dependency("abi_render", .{}).module("abi"));
}
