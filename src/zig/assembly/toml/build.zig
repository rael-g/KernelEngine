const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_assembly_toml",
        .root = "src/assembly_toml.zig",
        .abi = &.{ "abi_assembly", "abi_assembly_toml_factory", "abi_file_system", "abi_result" },
        .common = &.{"heap"},
        .packages = &.{.{ .name = "zsub", .dependency = "zsub", .module = "zsub" }},
        .translations = &.{.{ .name = "c", .header = "src/c.h" }},
        .third_party = thirdParty,
        .tests = "Run the TOML composition source unit tests",
    });
}

fn thirdParty(b: *std.Build, modules: ke_build.Modules) void {
    const tomlc99_dir = b.option([]const u8, "tomlc99-dir", "dir holding toml.c and toml.h, fetched by the root build.zig.zon") orelse @panic("-Dtomlc99-dir required");
    for (modules.all(b)) |mod| {
        mod.addIncludePath(.{ .cwd_relative = tomlc99_dir });
        mod.addCSourceFile(.{
            .file = .{ .cwd_relative = b.pathJoin(&.{ tomlc99_dir, "toml.c" }) },
            .flags = &.{ "-fno-sanitize=undefined", "-Werror", "-Wno-unused-command-line-argument" },
        });
    }
}
