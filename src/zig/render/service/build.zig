const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_service",
        .root = "src/render_service.zig",
        .abi = &.{ "abi_ecs", "abi_render", "abi_render_service_factory", "abi_resource_cache", "abi_resource_cache_default_factory", "abi_result" },
        .common = &.{"heap"},
        .stubs = &.{ "ecs", "render" },
        .render_common = &.{ "handle", "shader_files" },
        .translations = &.{.{ .name = "c", .header = "src/c.h" }},
        .third_party = thirdParty,
        .tests = "Run the render service unit tests",
    });
}

fn thirdParty(b: *std.Build, modules: ke_build.Modules) void {
    const ke_lib_dir = b.option([]const u8, "ke-lib-dir", "dir holding the built ke_resource_cache_default library") orelse @panic("-Dke-lib-dir required");
    for (modules.all(b)) |mod| {
        mod.addLibraryPath(.{ .cwd_relative = ke_lib_dir });
        mod.linkSystemLibrary("ke_resource_cache_default", .{});
        mod.addRPathSpecial("$ORIGIN");
    }
}
