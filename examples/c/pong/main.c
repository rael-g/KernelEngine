#include "pong.h"

#include <kernel_engine/sdk/defaults.h>

#include <stdio.h>

int main(void)
{
    const ke_sdk_engine_desc desc = {
        .task_pool = ke_sdk_task_pool_enki,
        .job_system = ke_sdk_job_system_enki,
        .file_system = ke_sdk_file_system_std,
        .io = ke_sdk_io_async,
        .configuration = ke_sdk_configuration_toml,
        .async = ke_sdk_async_enki,
        .input = ke_sdk_input,
        .window = ke_sdk_window_glfw,
        .ecs = ke_sdk_ecs_flecs,
        .scheduler = ke_sdk_scheduler,
        .schedule = ke_sdk_schedule,
        .runtime = ke_sdk_runtime,
        .gpu_device = ke_sdk_gpu_device_webgpu,
        .render_target = ke_sdk_render_target_webgpu_window,
        .fonts = ke_sdk_fonts_stb,
        .assets = ke_sdk_assets,
        .scene_tree = ke_sdk_scene_tree,
        .render_service = ke_sdk_render_service,
        .gbuffer = ke_sdk_gbuffer,
        .deferred_lighting = ke_sdk_deferred_lighting,
        .forward = ke_sdk_forward,
        .tonemap = ke_sdk_tonemap,
        .ui = ke_sdk_ui,
        .labels = ke_sdk_labels,
        .physics = ke_sdk_physics_box2d,
        .audio = ke_sdk_audio_miniaudio,
        .actions = ke_sdk_actions,
        .node_types = ke_sdk_node_types,
        .scene_files = ke_sdk_scene_files,
        .extraction = ke_sdk_extraction,
    };
    ke_sdk_default_engine parts;
    ke_sdk_engine *engine = &parts.engine;
    ke_result made = ke_sdk_engine_create(&desc, "pong", engine);
    if (made == KE_OK)
    {
        pong_game game = { .types = engine->node_types.ref };
        made = pong_register(&game);
    }
    if (made == KE_OK) made = ke_sdk_engine_run(engine, NULL);
    ke_sdk_engine_destroy(engine);
    if (made != KE_OK)
    {
        fprintf(stderr, "pong failed with result code 0x%08x\n", (unsigned)made);
        return 1;
    }
    return 0;
}
