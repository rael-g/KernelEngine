const std = @import("std");
const ke_build = @import("ke_build");

pub fn build(b: *std.Build) void {
    _ = ke_build.plugin(b, .{
        .name = "ke_resource_cache_default",
        .root = "src/resource_cache.zig",
        .abi = &.{ "abi_resource_cache", "abi_result" },
        .common = &.{"heap"},
        .tests = "Run the default resource cache unit tests",
    });
}
