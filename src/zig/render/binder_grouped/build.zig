const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_render_binder_grouped",
        .root = "src/resource_binder_grouped.zig",
        .abi = &.{ "abi_render_gpu", "abi_asset_resolver", "abi_io", "abi_render", "abi_render_binder_grouped_factory", "abi_result" },
        .common = &.{"heap"},
        .translations = &.{.{ .name = "c", .header = "src/c.h" }},
        .third_party = materialParams,
        .packages = &.{.{ .name = "zsub", .dependency = "zsub", .module = "zsub" }},
        .tests = "Run the grouped resource binder unit tests",
    });
}

fn materialParams(b: *std.Build, modules: ke_build.Modules) void {
    const json = b.option([]const u8, "material-params-json", "generated reflection of the material parameter block") orelse @panic("-Dmaterial-params-json required");
    for (modules.all(b)) |mod| {
        mod.addAnonymousImport("material_params.json", .{ .root_source_file = .{ .cwd_relative = json } });
    }
}
