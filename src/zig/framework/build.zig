const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_framework",
        .root = "src/framework_root.zig",
        .abi = &.{ "abi_framework_components", "abi_spatial_contract", "abi_render_contract", "abi_physics_contract", "abi_framework", "abi_audio_contract", "abi_ui_components", "abi_scene_tree", "abi_render_material", "abi_render_handles", "abi_render_components", "abi_physics_components", "abi_mesh_data", "abi_mesh", "abi_input_actions", "abi_configuration", "abi_image_loader", "abi_ecs_variant", "abi_audio_components", "abi_asset_resolver", "abi_audio", "abi_ecs", "abi_framework_factory", "abi_input", "abi_io", "abi_math", "abi_physics", "abi_render", "abi_result", "abi_runtime", "abi_spatial", "abi_text" },
        .common = &.{"heap"},
        .translations = &.{.{ .name = "c", .header = "src/c.h" }},
        .packages = &.{.{ .name = "zsub", .dependency = "zsub", .module = "zsub" }},
        .third_party = thirdParty,
        .tests = "Run unit tests",
    });
}

fn thirdParty(b: *std.Build, modules: ke_build.Modules) void {
    const tomlc99_dir = b.option([]const u8, "tomlc99-dir", "dir holding toml.c and toml.h, fetched by the root build.zig.zon") orelse @panic("-Dtomlc99-dir required");
    for (modules.all(b)) |mod| {
        addTomlc99(b, mod, tomlc99_dir);
    }
}

fn addTomlc99(b: *std.Build, mod: *std.Build.Module, dir: []const u8) void {
    mod.addIncludePath(.{ .cwd_relative = dir });
    mod.addCSourceFile(.{
        .file = .{ .cwd_relative = b.pathJoin(&.{ dir, "toml.c" }) },
        .flags = &.{ "-fno-sanitize=undefined", "-Werror", "-Wno-unused-command-line-argument" },
    });
}
