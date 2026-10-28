const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    ke_build.plugin(b, .{
        .name = "ke_asset_stb_image",
        .root = "src/stb_image_loader.zig",
        .abi = &.{ "abi_asset", "abi_asset_stb_image_factory", "abi_result" },
        .common = &.{"heap"},
        .translations = &.{.{ .name = "c", .header = "src/c.h" }},
        .third_party = thirdParty,
        .tests = "Run the stb_image loader unit tests",
    });
}

fn thirdParty(b: *std.Build, mod: *std.Build.Module) void {
    const stb_include = b.option([]const u8, "stb-include", "vcpkg stb_image.h include dir") orelse @panic("-Dstb-include required");
    mod.addIncludePath(.{ .cwd_relative = stb_include });
    const implementation = b.addWriteFiles().add("stb_image_impl.c", "#define STB_IMAGE_IMPLEMENTATION\n#include <stb_image.h>\n");
    mod.addCSourceFile(.{ .file = implementation, .flags = &.{ "-fno-sanitize=undefined", "-Werror", "-Wno-unused-command-line-argument" } });
}
