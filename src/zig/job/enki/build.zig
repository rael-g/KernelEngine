const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_job_system_enki",
        .root = "src/job_system_enki.zig",
        .abi = &.{ "abi_part", "abi_completion", "abi_job", "abi_job_system_enki_factory", "abi_result", "abi_settings" },
        .common = &.{"heap"},
        .packages = &.{ .{ .name = "part", .dependency = "ke_part", .module = "part" }, .{ .name = "settings_schema", .dependency = "ke_settings_schema", .module = "settings_schema" },  .{ .name = "completion_graph", .dependency = "ke_completion_graph", .module = "completion_graph" }, .{ .name = "job_suite", .dependency = "ke_job_suite", .module = "job_suite" } },
        .translations = &.{.{ .name = "c", .header = "src/c.h" }},
        .third_party = thirdParty,
        .tests = "Run the enkiTS job system unit tests",
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
