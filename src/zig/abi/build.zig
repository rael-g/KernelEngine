const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const tests = b.step("test", "Check the ABI of every domain against the headers");
    inline for (.{
        "abi_asset_loader",
        "abi_asset_resolver",
        "abi_audio",
        "abi_audio_components",
        "abi_audio_contract",
        "abi_configuration",
        "abi_ecs",
        "abi_ecs_variant",
        "abi_file_system",
        "abi_framework",
        "abi_framework_components",
        "abi_image_loader",
        "abi_input",
        "abi_input_actions",
        "abi_io",
        "abi_logger",
        "abi_math",
        "abi_mesh",
        "abi_mesh_data",
        "abi_physics",
        "abi_physics_components",
        "abi_physics_contract",
        "abi_render",
        "abi_render_components",
        "abi_render_contract",
        "abi_render_gpu",
        "abi_render_handles",
        "abi_render_material",
        "abi_render_ui",
        "abi_resource_cache",
        "abi_result",
        "abi_runtime",
        "abi_scene_loader",
        "abi_scene_tree",
        "abi_script_host",
        "abi_signal_bus",
        "abi_spatial",
        "abi_spatial_contract",
        "abi_task_pool",
        "abi_text",
        "abi_ui_components",
        "abi_view",
        "abi_window",
        "abi_world",
    }) |name| {
        const domain = b.dependency(name, .{ .target = target, .optimize = optimize });
        tests.dependOn(&domain.builder.top_level_steps.get("test").?.step);
    }
}
