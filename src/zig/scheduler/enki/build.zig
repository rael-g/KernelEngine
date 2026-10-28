const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_scheduler_enki",
        .root = "src/enki_scheduler.zig",
        .abi = &.{ "abi_result", "abi_scheduler", "abi_scheduler_enki_factory" },
        .common = &.{"heap"},
        .translations = &.{.{ .name = "c", .header = "src/c.h" }},
        .third_party = thirdParty,
        .tests = "Run the enkiTS scheduler unit tests",
    });
}

fn thirdParty(b: *std.Build, modules: ke_build.Modules) void {
    const enki_include = b.option([]const u8, "enki-include", "enkiTS headers dir") orelse @panic("-Denki-include required");
    const enki_lib = b.option([]const u8, "enki-lib", "dir holding the enkiTS library") orelse @panic("-Denki-lib required");
    for (modules.all(b)) |mod| {
        mod.addIncludePath(.{ .cwd_relative = enki_include });

        mod.link_libcpp = true;
        mod.addLibraryPath(.{ .cwd_relative = enki_lib });
        mod.linkSystemLibrary("enkiTS", .{});
    }
}
