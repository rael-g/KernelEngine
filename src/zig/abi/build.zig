const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const tests = b.step("test", "Check every contract domain's ABI against its headers");
    inline for (.{
        "ke_abi_asset",
        "ke_abi_audio",
        "ke_abi_configuration",
        "ke_abi_ecs",
        "ke_abi_framework",
        "ke_abi_input",
        "ke_abi_logger",
        "ke_abi_math",
        "ke_abi_physics",
        "ke_abi_render",
        "ke_abi_resource_cache",
        "ke_abi_result",
        "ke_abi_runtime",
        "ke_abi_scheduler",
        "ke_abi_spatial",
        "ke_abi_text",
        "ke_abi_view",
        "ke_abi_window",
    }) |name| {
        const domain = b.dependency(name, .{ .target = target, .optimize = optimize });
        tests.dependOn(&domain.builder.top_level_steps.get("test").?.step);
    }
}
