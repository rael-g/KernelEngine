const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_text_stb_truetype",
        .root = "src/stb_font.zig",
        .abi = &.{ "abi_result", "abi_text" },
        .common = &.{"heap"},
        .translations = &.{.{ .name = "c", .header = "src/c.h" }},
        .third_party = thirdParty,
        .tests = "Run the stb_truetype font loader unit tests",
    });
}

fn thirdParty(b: *std.Build, modules: ke_build.Modules) void {
    const stb_include = b.option([]const u8, "stb-include", "vcpkg stb_truetype.h include dir") orelse @panic("-Dstb-include required");
    for (modules.all(b)) |mod| {
        mod.addIncludePath(.{ .cwd_relative = stb_include });
        const implementation = b.addWriteFiles().add("stb_font_impl.c", "#define STB_TRUETYPE_IMPLEMENTATION\n#include <stb_truetype.h>\n");
        mod.addCSourceFile(.{ .file = implementation, .flags = &.{ "-fno-sanitize=undefined", "-Werror", "-Wno-unused-command-line-argument" } });
    }
}
