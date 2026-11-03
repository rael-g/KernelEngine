const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("object_uniforms", .{ .root_source_file = b.path("object_uniforms.zig"), .target = target, .optimize = optimize });
    mod.addImport("abi_asset_resolver", b.dependency("abi_asset_resolver", .{}).module("abi"));
    mod.addImport("abi_render_gpu", b.dependency("abi_render_gpu", .{}).module("abi"));
    mod.addImport("abi_render", b.dependency("abi_render", .{}).module("abi"));
    mod.addImport("abi_result", b.dependency("abi_result", .{}).module("abi"));
}
