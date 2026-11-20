#include "pong.h"

#include <kernel_engine/assembly/default/assembly_default_create.h>
#include <kernel_engine/async/enki/async_enki_parts.h>
#include <kernel_engine/audio/miniaudio/audio_miniaudio_parts.h>
#include <kernel_engine/audio/module/audio_module_parts.h>
#include <kernel_engine/configuration/configuration_create.h>
#include <kernel_engine/configuration/toml/configuration_toml.h>
#include <kernel_engine/ecs/ecs_flecs_parts.h>
#include <kernel_engine/engine_nodes/engine_nodes_parts.h>
#include <kernel_engine/extraction/default/extraction_default_parts.h>
#include <kernel_engine/file_system/std/file_system_std_create.h>
#include <kernel_engine/framework/framework_parts.h>
#include <kernel_engine/input/default/input_default_parts.h>
#include <kernel_engine/io/std/io_std_parts.h>
#include <kernel_engine/job/enki/job_system_enki_parts.h>
#include <kernel_engine/physics/body2d/physics_body2d_parts.h>
#include <kernel_engine/physics/box2d/physics_2d_box2d_parts.h>
#include <kernel_engine/render/binder_grouped/render_binder_grouped_parts.h>
#include <kernel_engine/render/camera/render_camera_parts.h>
#include <kernel_engine/render/deferred_lighting/render_deferred_lighting_parts.h>
#include <kernel_engine/render/forward/render_forward_parts.h>
#include <kernel_engine/render/frame/render_frame_parts.h>
#include <kernel_engine/render/gbuffer/render_gbuffer_parts.h>
#include <kernel_engine/render/scene/render_scene_parts.h>
#include <kernel_engine/render/service/render_service_parts.h>
#include <kernel_engine/render/tonemap/render_tonemap_parts.h>
#include <kernel_engine/render/ui/render_ui_parts.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_parts.h>
#include <kernel_engine/render_graph/simple/render_graph_simple_parts.h>
#include <kernel_engine/runner/runner.h>
#include <kernel_engine/runner/window/runner_window_parts.h>
#include <kernel_engine/schedule/schedule_parts.h>
#include <kernel_engine/scheduler/scheduler_parts.h>
#include <kernel_engine/sdk/paths.h>
#include <kernel_engine/text/stb_truetype/text_stb_truetype_parts.h>
#include <kernel_engine/view/space/view_space_parts.h>
#include <kernel_engine/window/glfw/window_glfw_parts.h>

#include <stdio.h>

enum { PATH_CAPACITY = 4096 };

typedef const ke_part *(*parts_fn)(size_t *out_count);

static pong_game game;

static void print_log(void *ctx, ke_log_level level, const char *scope, const char *message)
{
    (void)ctx;
    fprintf(stderr, "[%s] (%d): %s\n", scope, (int)level, message);
}

static void print_failure(void *ctx, ke_assembly_failure failure, const char *instance, const char *name, const char *detail)
{
    (void)ctx;
    fprintf(stderr, "unresolved (%d): %s %s: %s\n", (int)failure, instance ? instance : "-", name ? name : "-", detail);
}

static void pong_release(void *ref)
{
    (void)ref;
}

static ke_result pong_create(const ke_part *self, const ke_part_bound *slots, ke_settings *settings, ke_owner *out)
{
    (void)self;
    (void)settings;
    game.types = slots[0].instances[0];
    ke_result made = pong_register(&game);
    if (made == KE_OK) *out = (ke_owner){ .ref = &game, .destroy = pong_release };
    return made;
}

static const ke_part_slot pong_slots[] = { { .name = "node_types", .contract = "ke_node_types", .cardinality = KE_PART_CARDINALITY_ONE } };

static const ke_part pong_part = { .name = "pong_nodes", .slots = pong_slots, .slot_count = 1, .create = pong_create };

static ke_result add_parts(ke_assembly *a)
{
    static const parts_fn libraries[] = {
        ke_job_system_enki_parts, ke_async_enki_parts, ke_io_std_parts, ke_input_default_parts, ke_ecs_flecs_parts,
        ke_schedule_parts, ke_scheduler_parts, ke_framework_parts, ke_engine_nodes_parts, ke_physics_2d_box2d_parts,
        ke_physics_body2d_parts, ke_extraction_default_parts, ke_window_glfw_parts, ke_gpu_device_webgpu_parts,
        ke_render_binder_grouped_parts, ke_render_service_parts, ke_render_graph_simple_parts, ke_view_space_parts,
        ke_render_camera_parts, ke_render_scene_parts, ke_render_frame_parts, ke_render_gbuffer_parts,
        ke_render_deferred_lighting_parts, ke_render_forward_parts, ke_render_tonemap_parts, ke_render_ui_parts,
        ke_text_stb_truetype_parts, ke_audio_miniaudio_parts, ke_audio_module_parts, ke_runner_window_parts,
    };
    ke_result made = KE_OK;
    for (size_t i = 0; made == KE_OK && i < sizeof libraries / sizeof libraries[0]; ++i)
    {
        size_t count = 0;
        const ke_part *all = libraries[i](&count);
        for (size_t j = 0; made == KE_OK && j < count; ++j) made = a->add_part(a, &all[j]);
    }
    return made == KE_OK ? a->add_part(a, &pong_part) : made;
}

static ke_result compose(ke_assembly *a)
{
    static const char *const instances[][3] = {
        { "job", "job_system_enki", "job" },
        { "async", "async_enki", "async" },
        { "io", "io_std", "io" },
        { "input", "input_default", NULL },
        { "world", "ecs_flecs", "ecs" },
        { "render_world", "ecs_flecs", "ecs" },
        { "startup", "schedule", "schedule" },
        { "pre_update", "schedule", "schedule" },
        { "fixed_pre_update", "schedule", "schedule" },
        { "fixed_update", "schedule", "schedule" },
        { "fixed_post_update", "schedule", "schedule" },
        { "update", "schedule", "schedule" },
        { "post_update", "schedule", "schedule" },
        { "render_begin", "schedule", "schedule" },
        { "render_prepare", "schedule", "schedule" },
        { "render_queue", "schedule", "schedule" },
        { "render_submit", "schedule", "schedule" },
        { "shutdown", "schedule", "schedule" },
        { "scheduler", "scheduler", "scheduler" },
        { "layout", "scheduler_layout", NULL },
        { "extraction", "extraction", NULL },
        { "extraction_history", "extraction_history", NULL },
        { "scene_tree", "scene_tree", NULL },
        { "hierarchy", "scene_hierarchy", NULL },
        { "physics", "physics_2d_box2d", "physics" },
        { "bodies", "physics_body2d", NULL },
        { "actions", "input_actions", "actions" },
        { "action_evaluation", "input_actions_evaluation", NULL },
        { "node_types", "node_types", NULL },
        { "node_systems", "node_types_systems", NULL },
        { "engine_nodes", "engine_nodes", NULL },
        { "pong_nodes", "pong_nodes", NULL },
        { "fonts", "font_loader_stb", NULL },
        { "assets", "asset_resolver", NULL },
        { "scene_files", "scene_files", "scene_files" },
        { "window", "window_glfw", "window" },
        { "device", "gpu_device_webgpu", "device" },
        { "target", "gpu_render_target_webgpu_window", "target" },
        { "binder", "render_binder_grouped", "binder" },
        { "service", "render_service", "service" },
        { "graph", "render_graph_simple", NULL },
        { "view_space", "view_space_rh", NULL },
        { "camera", "render_camera", NULL },
        { "scene", "render_scene_resolve", NULL },
        { "scene_systems", "render_scene_resolve_systems", NULL },
        { "frame", "render_frame", "frame" },
        { "frame_systems", "render_frame_systems", NULL },
        { "gbuffer", "render_gbuffer", NULL },
        { "deferred_lighting", "render_deferred_lighting", "deferred_lighting" },
        { "forward", "render_forward", "forward" },
        { "tonemap", "render_tonemap", NULL },
        { "ui", "render_ui", NULL },
        { "ui_systems", "render_ui_systems", NULL },
        { "labels", "render_label_resolve", "labels" },
        { "audio", "audio_miniaudio", NULL },
        { "sound", "sound", NULL },
        { "runner", "runner_window", NULL },
    };
    ke_result made = KE_OK;
    for (size_t i = 0; made == KE_OK && i < sizeof instances / sizeof instances[0]; ++i)
        made = a->add_instance(a, instances[i][0], instances[i][1], instances[i][2]);
    if (made == KE_OK) made = a->set_default(a, "ke_ecs", "world");

    static const char *const cadences[][2] = {
        { "startup", "startup" },
        { "every_tick", "pre_update" },
        { "fixed", "fixed_pre_update" },
        { "fixed", "fixed_update" },
        { "fixed", "fixed_post_update" },
        { "every_tick", "update" },
        { "every_tick", "post_update" },
        { "every_tick", "extraction" },
        { "every_tick", "render_begin" },
        { "every_tick", "render_prepare" },
        { "every_tick", "render_queue" },
        { "every_tick", "render_submit" },
        { "shutdown", "shutdown" },
    };
    for (size_t i = 0; made == KE_OK && i < sizeof cadences / sizeof cadences[0]; ++i)
        made = a->bind(a, "layout", cadences[i][0], cadences[i][1]);
    for (size_t i = 1; made == KE_OK && i < sizeof cadences / sizeof cadences[0]; ++i)
        made = a->order(a, "layout", NULL, cadences[i - 1][1], cadences[i][1]);

    static const char *const binds[][3] = {
        { "render_begin", "ecs", "render_world" },
        { "render_prepare", "ecs", "render_world" },
        { "render_queue", "ecs", "render_world" },
        { "render_submit", "ecs", "render_world" },
        { "extraction", "render", "render_world" },
        { "scene", "render", "render_world" },
        { "frame", "ecs", "render_world" },
        { "ui", "render", "render_world" },
        { "hierarchy", "post_update", "post_update" },
        { "action_evaluation", "pre_update", "pre_update" },
        { "node_systems", "pre_update", "pre_update" },
        { "node_systems", "fixed_update", "fixed_update" },
        { "node_systems", "update", "update" },
        { "node_systems", "post_update", "post_update" },
        { "bodies", "fixed_post_update", "fixed_post_update" },
        { "extraction_history", "fixed_pre_update", "fixed_pre_update" },
        { "scene_files", "first_scene", "startup" },
        { "scene_systems", "update", "update" },
        { "scene_systems", "post_update", "post_update" },
        { "labels", "update", "update" },
        { "sound", "post_update", "post_update" },
        { "frame_systems", "render_begin", "render_begin" },
        { "frame_systems", "render_submit", "render_submit" },
        { "gbuffer", "render_prepare", "render_prepare" },
        { "gbuffer", "render_queue", "render_queue" },
        { "deferred_lighting", "render_queue", "render_queue" },
        { "forward", "render_queue", "render_queue" },
        { "tonemap", "render_queue", "render_queue" },
        { "ui_systems", "render_prepare", "render_prepare" },
        { "ui_systems", "render_queue", "render_queue" },
    };
    for (size_t i = 0; made == KE_OK && i < sizeof binds / sizeof binds[0]; ++i) made = a->bind(a, binds[i][0], binds[i][1], binds[i][2]);
    return made;
}

static ke_result paths(ke_configuration *configuration, const char *project_dir)
{
    char shader_dir[PATH_CAPACITY];
    char font[PATH_CAPACITY + 64];
    if (!ke_sdk_beside_executable(shader_dir, sizeof shader_dir, "shaders")) return KE_RESULT_NOT_FOUND;
    snprintf(font, sizeof font, "%s/assets/fonts/LiberationSans-Regular.ttf", project_dir);
    ke_result made = configuration->set_string(configuration, "binder", "shader_dir", shader_dir);
    if (made == KE_OK) made = configuration->set_string(configuration, "service", "shader_dir", shader_dir);
    if (made == KE_OK) made = configuration->set_string(configuration, "labels", "default_font", font);
    return made;
}

static ke_result play(ke_configuration *configuration, ke_file_system *files)
{
    ke_assembly_handle assembly;
    ke_result made = ke_assembly_default_create(configuration, &assembly);
    if (made != KE_OK) return made;
    ke_assembly *a = assembly.ref;
    made = a->route_log(a, print_log, NULL);
    if (made == KE_OK) made = a->add_external(a, "file_system", "ke_file_system", files);
    if (made == KE_OK) made = add_parts(a);
    if (made == KE_OK) made = compose(a);
    if (made == KE_OK) made = a->resolve(a, print_failure, NULL);
    if (made == KE_OK) made = KE_RESULT_PENDING;
    while (made == KE_RESULT_PENDING) made = a->advance(a);
    void *runner = NULL;
    if (made == KE_OK) made = a->get(a, "runner", "ke_runner", &runner);
    if (made == KE_OK) made = ((ke_runner *)runner)->run(runner);
    assembly.destroy(assembly.ref);
    return made;
}

int main(void)
{
    char project_dir[PATH_CAPACITY];
    char project_file[PATH_CAPACITY + 16];
    if (!ke_sdk_beside_executable(project_dir, sizeof project_dir, "pong"))
    {
        fprintf(stderr, "pong: the project directory beside the executable is missing\n");
        return 1;
    }
    snprintf(project_file, sizeof project_file, "%s/Project", project_dir);

    ke_file_system_handle files = { 0 };
    ke_configuration_handle configuration = { 0 };
    ke_configuration_source_handle source = { 0 };
    ke_result made = ke_file_system_std_create(project_dir, &files);
    if (made == KE_OK) made = ke_configuration_create(&configuration);
    if (made == KE_OK) made = ke_configuration_toml_create(files.ref, &source);
    if (made == KE_OK) made = source.ref->load(source.ref, configuration.ref, project_file);
    if (made == KE_OK) made = paths(configuration.ref, project_dir);
    if (made == KE_OK) made = play(configuration.ref, files.ref);
    if (source.destroy) source.destroy(source.ref);
    if (configuration.destroy) configuration.destroy(configuration.ref);
    if (files.destroy) files.destroy(files.ref);
    if (made != KE_OK)
    {
        fprintf(stderr, "pong failed with result code 0x%08x\n", (unsigned)made);
        return 1;
    }
    return 0;
}
