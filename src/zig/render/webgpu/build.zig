const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_gpu_device_webgpu",
        .root = "src/gpu_device_webgpu.zig",
        .abi = &.{ "abi_gpu_device_webgpu_factory", "abi_render", "abi_result", "abi_task_pool", "abi_window" },
        .common = &.{"heap"},
        .translations = &.{.{ .name = "c", .header = "src/c.h" }},
        .third_party = thirdParty,
        .tests = "Run unit tests",
    });
}

fn thirdParty(b: *std.Build, modules: ke_build.Modules) void {
    const wgpu_inc = b.option([]const u8, "wgpu-include", "Path containing webgpu/webgpu.h") orelse @panic("-Dwgpu-include required");
    const wgpu_lib = b.option([]const u8, "wgpu-lib", "Path containing wgpu_native DLL/lib") orelse @panic("-Dwgpu-lib required");
    for (modules.all(b)) |mod| {
        mod.addIncludePath(.{ .cwd_relative = wgpu_inc });
        mod.addLibraryPath(.{ .cwd_relative = wgpu_lib });
        mod.addRPathSpecial("$ORIGIN");
        mod.linkSystemLibrary("wgpu_native", .{});
        if (mod.resolved_target.?.result.os.tag == .linux) {
            mod.linkSystemLibrary("X11", .{});
        }
    }
}
