const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_runtime",
        .root = "src/runtime.zig",
        .abi = &.{ "abi_framework", "abi_asset_resolver", "abi_asset_loader", "abi_ecs", "abi_result", "abi_runtime", "abi_runtime_factory", "abi_task_pool" },
        .common = &.{"heap"},
        .third_party = thirdParty,
        .tests = "Run unit tests",
    });
}

fn thirdParty(b: *std.Build, modules: ke_build.Modules) void {
    const ke_lib_dir = b.option([]const u8, "ke-lib-dir", "dir holding the built ke_ecs_flecs and ke_task_pool_enki libraries") orelse @panic("-Dke-lib-dir required");
    for (modules.tests) |mod| {
        mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
        mod.addRPath(.{ .cwd_relative = ke_lib_dir });
        mod.linkSystemLibrary("ke_ecs_flecs", .{});
        mod.linkSystemLibrary("ke_task_pool_enki", .{});
    }
}
