const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_physics_2d_box2d",
        .root = "src/box2d_physics.zig",
        .abi = &.{ "abi_configuration", "abi_physics", "abi_physics_2d_box2d_factory", "abi_result" },
        .common = &.{"heap"},
        .translations = &.{.{ .name = "box2d", .header = "src/box2d.h" }},
        .third_party = box2d,
        .tests = "Run the Box2D physics unit tests",
    });
}

fn box2d(b: *std.Build, modules: ke_build.Modules) void {
    const include = b.option([]const u8, "box2d-include", "Box2D headers dir") orelse @panic("-Dbox2d-include required");
    const library = b.option([]const u8, "box2d-lib", "absolute path to the Box2D library") orelse @panic("-Dbox2d-lib required");
    for (modules.all(b)) |mod| {
        mod.addIncludePath(.{ .cwd_relative = include });
        mod.addObjectFile(.{ .cwd_relative = library });
    }
}
