const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_gpu_render_target_renderdoc",
        .root = "src/renderdoc_target.zig",
        .abi = &.{ "abi_render_gpu", "abi_asset_resolver", "abi_gpu_render_target_renderdoc_factory", "abi_render", "abi_result" },
        .common = &.{"heap"},
        .translations = &.{.{ .name = "c", .header = "src/c.h" }},
        .third_party = thirdParty,
        .tests = "Run the renderdoc render target unit tests",
    });
}

fn thirdParty(b: *std.Build, modules: ke_build.Modules) void {
    const renderdoc_include = b.option([]const u8, "renderdoc-include", "directory holding renderdoc_app.h") orelse @panic("-Drenderdoc-include required");
    for (modules.all(b)) |mod| {
        mod.addIncludePath(.{ .cwd_relative = renderdoc_include });
    }
}
