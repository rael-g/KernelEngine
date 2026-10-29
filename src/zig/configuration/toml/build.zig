const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_configuration_toml",
        .root = "src/configuration_toml.zig",
        .abi = &.{ "abi_configuration", "abi_configuration_toml_factory", "abi_io", "abi_result" },
        .common = &.{"heap"},
        .packages = &.{.{ .name = "zsub", .dependency = "zsub", .module = "zsub" }},
        .translations = &.{.{ .name = "c", .header = "src/c.h" }},
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
