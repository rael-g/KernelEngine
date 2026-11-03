const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_asset_assimp",
        .root = "src/assimp_loader.zig",
        .abi = &.{ "abi_mesh_data", "abi_mesh", "abi_asset_loader", "abi_io", "abi_render", "abi_result", "abi_task_pool" },
        .translations = &.{.{ .name = "c", .header = "src/c.h" }},
        .packages = &.{.{ .name = "zsub", .dependency = "zsub", .module = "zsub" }},
        .third_party = thirdParty,
        .tests = "Run the assimp conversion unit tests",
    });
}

fn thirdParty(b: *std.Build, modules: ke_build.Modules) void {
    const assimp_include = b.option([]const u8, "assimp-include", "Assimp headers dir") orelse @panic("-Dassimp-include required");
    const assimp_libs = b.option([]const u8, "assimp-libs", "'|'-separated Assimp library paths") orelse @panic("-Dassimp-libs required");
    const stb_include = b.option([]const u8, "stb-include", "vcpkg stb_image.h include dir") orelse @panic("-Dstb-include required");
    for (modules.all(b)) |mod| {
        mod.link_libcpp = true;
        inline for (.{ assimp_include, stb_include }) |inc| {
            mod.addIncludePath(.{ .cwd_relative = inc });
        }

        var lib_it = std.mem.splitScalar(u8, assimp_libs, '|');
        while (lib_it.next()) |path| {
            if (path.len != 0) mod.addObjectFile(.{ .cwd_relative = path });
        }
    }
}
