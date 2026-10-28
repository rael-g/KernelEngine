const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_audio_miniaudio",
        .root = "src/miniaudio_audio.zig",
        .abi = &.{ "abi_audio", "abi_resource_cache", "abi_resource_cache_default_factory", "abi_result" },
        .common = &.{"heap"},
        .translations = &.{.{ .name = "c", .header = "src/c.h" }},
        .third_party = thirdParty,
        .tests = "Run the miniaudio audio unit tests",
    });
}

fn thirdParty(b: *std.Build, modules: ke_build.Modules) void {
    const miniaudio_include = b.option([]const u8, "miniaudio-include", "vcpkg miniaudio.h include dir") orelse @panic("-Dminiaudio-include required");
    const ke_resource_cache_lib_dir = b.option([]const u8, "ke-resource-cache-lib-dir", "dir with ke_resource_cache_default import lib") orelse @panic("-Dke-resource-cache-lib-dir required");
    for (modules.all(b)) |mod| {
        mod.addIncludePath(.{ .cwd_relative = miniaudio_include });
        const implementation = b.addWriteFiles().add("miniaudio_impl.c", "#define MINIAUDIO_IMPLEMENTATION\n#include <miniaudio.h>\n");
        mod.addCSourceFile(.{ .file = implementation, .flags = &.{ "-fno-sanitize=undefined", "-Werror", "-Wno-unused-command-line-argument" } });
        mod.addLibraryPath(.{ .cwd_relative = ke_resource_cache_lib_dir });
        mod.linkSystemLibrary("ke_resource_cache_default", .{});
        mod.addRPathSpecial("$ORIGIN");
        if (mod.resolved_target.?.result.os.tag == .windows) {
            mod.linkSystemLibrary("winmm", .{});
        }
    }
    for (modules.tests) |mod| mod.addRPath(.{ .cwd_relative = ke_resource_cache_lib_dir });
}
