const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_async_enki",
        .root = "src/async_enki.zig",
        .abi = &.{ "abi_completion", "abi_async", "abi_async_enki_factory", "abi_result" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "completion_graph", .dependency = "ke_completion_graph", .module = "completion_graph" }, .{ .name = "async_suite", .dependency = "ke_async_suite", .module = "async_suite" } },
        .translations = &.{.{ .name = "c", .header = "src/c.h" }},
        .third_party = thirdParty,
        .tests = "Run the enkiTS async system unit tests",
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
