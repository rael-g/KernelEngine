#ifndef KERNEL_ENGINE_SDK_ENGINE_H_
#define KERNEL_ENGINE_SDK_ENGINE_H_

#include <kernel_engine/audio/miniaudio/miniaudio_audio.h>
#include <kernel_engine/audio/module/sound_module.h>
#include <kernel_engine/configuration/configuration_create.h>
#include <kernel_engine/configuration/toml/configuration_toml.h>
#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/file_system/std/file_system_std_create.h>
#include <kernel_engine/framework/asset_resolver_create.h>
#include <kernel_engine/framework/engine_node_types.h>
#include <kernel_engine/framework/input_actions_create.h>
#include <kernel_engine/framework/node_types_create.h>
#include <kernel_engine/framework/scene_files_create.h>
#include <kernel_engine/framework/scene_tree_create.h>
#include <kernel_engine/input/default/input_default_create.h>
#include <kernel_engine/io/pool/io_pool_create.h>
#include <kernel_engine/physics/body2d/body2d_module.h>
#include <kernel_engine/physics/box2d/box2d_physics.h>
#include <kernel_engine/render/binder_grouped/resource_binder_grouped_create.h>
#include <kernel_engine/render/camera/camera_create.h>
#include <kernel_engine/render/cluster/cluster_create.h>
#include <kernel_engine/render/deferred_lighting/deferred_lighting_create.h>
#include <kernel_engine/render/forward/forward_create.h>
#include <kernel_engine/render/frame/frame_create.h>
#include <kernel_engine/render/gbuffer/gbuffer_create.h>
#include <kernel_engine/render/scene/label_resolve_create.h>
#include <kernel_engine/render/scene/scene_resolve_create.h>
#include <kernel_engine/render/service/render_service_create.h>
#include <kernel_engine/render/shadow/shadow_create.h>
#include <kernel_engine/render/tonemap/tonemap_create.h>
#include <kernel_engine/render/ui/ui_create.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <kernel_engine/render/webgpu/gpu_render_target_webgpu_window_create.h>
#include <kernel_engine/runtime/runtime_create.h>
#include <kernel_engine/sdk/paths.h>
#include <kernel_engine/task_pool/enki/enki_task_pool.h>
#include <kernel_engine/text/stb_truetype/stb_font.h>
#include <kernel_engine/view/space/view_space_rh_create.h>
#include <kernel_engine/window/glfw/glfw_window.h>

#include <stdio.h>
#include <string.h>
#include <time.h>

/**
 * @file
 * An engine made of the default parts, each configured by the project file's section for it, with any
 * part swapped for a function of the caller's that makes it from the parts made before it.
 */

/** The bytes each path an engine keeps can hold. */
#define KE_SDK_ENGINE_PATH_CAPACITY 1024

/** The render service and every pass the default renderer composes. */
typedef struct ke_sdk_renderer
{
    ke_render_resource_binder_handle   binder;
    ke_render_service_handle           service;
    ke_view_space_handle               view_space;
    ke_render_camera_handle            camera;
    ke_render_scene_resolve_handle     scene;
    ke_render_frame_handle             frame;
    ke_render_shadow_handle            shadow;
    ke_render_cluster_handle           cluster;
    ke_render_gbuffer_handle           gbuffer;
    ke_render_deferred_lighting_handle deferred;
    ke_render_forward_handle           forward;
    ke_render_tonemap_handle           tonemap;
    ke_render_ui_handle                ui;
    ke_render_label_resolve_handle     labels;
} ke_sdk_renderer;

/**
 * Every part of an engine, each an owner its part function wrote, and the paths they are made from. A part
 * function reads the parts made before its own and writes its own; ke_sdk_engine_destroy releases each one
 * whose ref is set, the last made first.
 */
typedef struct ke_sdk_engine
{
    char project_dir[KE_SDK_ENGINE_PATH_CAPACITY];
    char shader_dir[KE_SDK_ENGINE_PATH_CAPACITY];
    char default_font[KE_SDK_ENGINE_PATH_CAPACITY];

    ke_task_pool_handle            task_pool;
    ke_file_system_handle          file_system;
    ke_io_handle                   io;
    ke_configuration_handle        configuration;
    ke_configuration_source_handle configuration_source;
    ke_input_handle                input;
    ke_window_handle               window;
    ke_ecs_handle                  ecs;
    ke_runtime_handle              runtime;
    ke_gpu_device_handle           gpu_device;
    ke_gpu_render_target_handle    render_target;
    ke_font_loader_handle          fonts;
    ke_asset_resolver_handle       assets;
    ke_scene_tree_handle           scene_tree;
    ke_sdk_renderer                renderer;
    ke_physics_2d_handle           physics;
    ke_physics_body2d_module_handle bodies;
    ke_audio_handle                audio;
    ke_sound_module_handle         sounds;
    ke_input_actions_handle        actions;
    ke_node_types_handle           node_types;
    ke_scene_files_handle          scene_files;
} ke_sdk_engine;

/**
 * Makes one part of @p engine from the parts made before it and writes it into its field.
 * @return KE_OK, or the code of the part that failed.
 */
typedef ke_result (*ke_sdk_engine_part)(ke_sdk_engine *engine);

/** The function each part of an engine is made by, in the order they are made. */
typedef struct ke_sdk_engine_desc
{
    ke_sdk_engine_part task_pool;
    ke_sdk_engine_part file_system;
    ke_sdk_engine_part io;
    ke_sdk_engine_part configuration;
    ke_sdk_engine_part input;
    ke_sdk_engine_part window;
    ke_sdk_engine_part ecs;
    ke_sdk_engine_part runtime;
    ke_sdk_engine_part gpu_device;
    ke_sdk_engine_part render_target;
    ke_sdk_engine_part fonts;
    ke_sdk_engine_part assets;
    ke_sdk_engine_part scene_tree;
    ke_sdk_engine_part renderer;
    ke_sdk_engine_part physics;
    ke_sdk_engine_part audio;
    ke_sdk_engine_part actions;
    ke_sdk_engine_part node_types;
    ke_sdk_engine_part scene_files;
} ke_sdk_engine_desc;

/** The configuration the default parts read their sections from. */
static inline ke_configuration *ke_sdk_engine_config(ke_sdk_engine *e) { return e->configuration.ref; }

/** An enkiTS pool with one worker per hardware thread. */
static inline ke_result ke_sdk_default_task_pool(ke_sdk_engine *e)
{
    return ke_task_pool_enki_create(&(ke_task_pool_config){ .worker_count = KE_TASK_POOL_WORKERS_PER_HARDWARE_THREAD }, &e->task_pool);
}

/** The operating system's files, relative to the working directory. */
static inline ke_result ke_sdk_default_file_system(ke_sdk_engine *e)
{
    return ke_file_system_std_create(&(ke_file_system_config){ .root = "." }, &e->file_system);
}

/** Reads through the task pool. */
static inline ke_result ke_sdk_default_io(ke_sdk_engine *e)
{
    return ke_io_pool_create(e->task_pool.ref, e->file_system.ref, &e->io);
}

/** The configuration, loaded from the file Project in the project directory. */
static inline ke_result ke_sdk_default_configuration(ke_sdk_engine *e)
{
    char project_file[KE_SDK_ENGINE_PATH_CAPACITY + 16];
    snprintf(project_file, sizeof project_file, "%s/Project", e->project_dir);
    ke_result made = ke_configuration_create(&e->configuration);
    if (made == KE_OK) made = ke_configuration_toml_create(e->io.ref, &e->configuration_source);
    if (made == KE_OK) made = e->configuration_source.ref->load(e->configuration_source.ref, e->configuration.ref, project_file);
    return made;
}

/** The input every window event reaches. */
static inline ke_result ke_sdk_default_input(ke_sdk_engine *e)
{
    return ke_input_create(&e->input);
}

/** A GLFW window titled and sized by `runtime.window`. */
static inline ke_result ke_sdk_default_window(ke_sdk_engine *e)
{
    ke_configuration *c = ke_sdk_engine_config(e);
    const ke_window_config config = {
        .title = c->get_string(c, "runtime.window", "title", "KernelEngine"),
        .width = (int32_t)c->get_int(c, "runtime.window", "width", 1280),
        .height = (int32_t)c->get_int(c, "runtime.window", "height", 720),
        .fullscreen = c->get_bool(c, "runtime.window", "fullscreen", false),
    };
    return ke_window_glfw_create(e->input.ref, &config, &e->window);
}

/** A flecs world. */
static inline ke_result ke_sdk_default_ecs(ke_sdk_engine *e)
{
    return ke_ecs_flecs_create(&(ke_ecs_config){ .reserved_id_capacity = 1048576 }, &e->ecs);
}

/** The runtime, its timestep from `runtime`. */
static inline ke_result ke_sdk_default_runtime(ke_sdk_engine *e)
{
    ke_configuration *c = ke_sdk_engine_config(e);
    const ke_runtime_config config = {
        .fixed_dt = (float)c->get_double(c, "runtime", "fixed_dt", 1.0 / 60.0),
        .fixed_dt_max_accum = (float)c->get_double(c, "runtime", "fixed_dt_max_accum", 0.25),
        .max_systems_per_phase = (uint32_t)c->get_int(c, "runtime", "max_systems_per_phase", 256),
    };
    return ke_runtime_create(e->ecs.ref, e->task_pool.ref, &config, &e->runtime);
}

/** A WebGPU device. */
static inline ke_result ke_sdk_default_gpu_device(ke_sdk_engine *e)
{
    return ke_gpu_device_webgpu_create(NULL, &(ke_gpu_device_config){ .enable_validation = false, .debug_labels = false }, &e->gpu_device);
}

/** The window's swapchain, presenting as `runtime.renderer.present_mode` says. */
static inline ke_result ke_sdk_default_render_target(ke_sdk_engine *e)
{
    ke_configuration *c = ke_sdk_engine_config(e);
    const bool mailbox = strcmp(c->get_string(c, "runtime.renderer", "present_mode", "fifo"), "mailbox") == 0;
    const ke_gpu_render_target_window_config config = { .present_mode = mailbox ? KE_GPU_PRESENT_MODE_MAILBOX : KE_GPU_PRESENT_MODE_FIFO };
    return ke_gpu_render_target_webgpu_window_create(e->gpu_device.ref, e->window.ref, &config, &e->render_target);
}

/** stb_truetype fonts. */
static inline ke_result ke_sdk_default_fonts(ke_sdk_engine *e)
{
    return ke_font_loader_stb_create(e->io.ref, &e->fonts);
}

/** Assets resolved under the project directory. */
static inline ke_result ke_sdk_default_assets(ke_sdk_engine *e)
{
    return ke_asset_resolver_create(NULL, e->fonts.ref, e->project_dir, e->io.ref, &e->assets);
}

/** The scene tree. */
static inline ke_result ke_sdk_default_scene_tree(ke_sdk_engine *e)
{
    return ke_scene_tree_create(e->ecs.ref, e->runtime.ref, &e->scene_tree);
}

/** The render service, cleared to `render.clear_color`, and the deferred and forward passes, the tonemap, the UI and its labels. */
static inline ke_result ke_sdk_default_renderer(ke_sdk_engine *e)
{
    ke_configuration *c = ke_sdk_engine_config(e);
    ke_sdk_renderer *r = &e->renderer;
    ke_gpu_device *gpu = e->gpu_device.ref;
    const ke_render_service_config service_config = {
        .shader_dir = e->shader_dir,
        .color_format = KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT,
        .depth_format = KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
        .clear_color = {
            (float)c->get_double(c, "render", "clear_color.0", 0.0),
            (float)c->get_double(c, "render", "clear_color.1", 0.0),
            (float)c->get_double(c, "render", "clear_color.2", 0.0),
            (float)c->get_double(c, "render", "clear_color.3", 1.0),
        },
    };
    ke_result made = ke_render_resource_binder_grouped_create(gpu, e->io.ref, &(ke_render_resource_binder_grouped_config){ .shader_dir = e->shader_dir }, &r->binder);
    if (made == KE_OK) made = ke_render_service_create(gpu, e->render_target.ref, e->ecs.ref, e->io.ref, r->binder.ref, &service_config, &r->service);
    if (made == KE_OK) made = ke_view_space_rh_create(&r->view_space);
    if (made == KE_OK) made = ke_render_camera_create(r->view_space.ref, gpu, &r->camera);
    if (made == KE_OK) made = ke_render_scene_resolve_create(e->runtime.ref, e->ecs.ref, r->service.ref, NULL, &r->scene);
    if (made == KE_OK) made = ke_render_frame_create(e->runtime.ref, e->ecs.ref, r->service.ref, r->camera.ref, r->scene.ref, &r->frame);
    if (made != KE_OK) return made;
    const ke_render_context context = {
        .runtime = e->runtime.ref, .ecs = e->ecs.ref, .service = r->service.ref, .device = gpu, .view_space = r->view_space.ref,
        .camera = r->camera.ref, .scene = r->scene.ref, .frame = r->frame.ref,
    };
    ke_render_shadow_resources shadow;
    ke_render_cluster_resources clusters;
    ke_render_gbuffer_resources gbuffer;
    made = ke_render_shadow_create(&context, &(ke_render_shadow_config){ .resolution = 1024, .light_distance = 25.0f, .extent = 20.0f, .near_plane = 0.1f, .far_plane = 50.0f }, &shadow, &r->shadow);
    if (made == KE_OK) made = ke_render_cluster_create(&context, &(ke_render_cluster_config){ .grid_x = 16, .grid_y = 9, .grid_z = 24, .max_lights_per_cluster = 64 }, &clusters, &r->cluster);
    if (made == KE_OK) made = ke_render_gbuffer_create(&context, &gbuffer, &r->gbuffer);
    if (made == KE_OK) made = ke_render_deferred_lighting_create(&context, &gbuffer, &shadow, &clusters, &(ke_render_deferred_lighting_config){ .ibl_enabled = true }, &r->deferred);
    if (made == KE_OK) made = ke_render_forward_create(&context, &shadow, &clusters, &(ke_render_forward_config){ .ibl_enabled = true }, &r->forward);
    if (made == KE_OK) made = ke_render_tonemap_create(&context, &r->tonemap);
    if (made == KE_OK) made = ke_render_ui_create(&context, &r->ui);
    if (made == KE_OK) made = ke_render_label_resolve_create(&context, r->ui.ref, e->assets.ref, &(ke_render_label_resolve_config){ .default_font = e->default_font }, &r->labels);
    return made;
}

/** A Box2D world with the gravity of `runtime.physics_2d`, and the module syncing bodies. */
static inline ke_result ke_sdk_default_physics(ke_sdk_engine *e)
{
    ke_configuration *c = ke_sdk_engine_config(e);
    const ke_physics_2d_config config = {
        .gravity_x = (float)c->get_double(c, "runtime.physics_2d", "gravity_x", 0.0),
        .gravity_y = (float)c->get_double(c, "runtime.physics_2d", "gravity_y", 0.0),
    };
    ke_result made = ke_physics_2d_box2d_create(&config, &e->physics);
    if (made == KE_OK) made = ke_physics_body2d_module_create(e->runtime.ref, e->ecs.ref, e->physics.ref, e->scene_tree.ref, &e->bodies);
    return made;
}

/** miniaudio, and the module playing the sound components, their clips under the project directory. */
static inline ke_result ke_sdk_default_audio(ke_sdk_engine *e)
{
    ke_result made = ke_audio_miniaudio_create(e->io.ref, &e->audio);
    if (made == KE_OK) made = ke_sound_module_create(e->runtime.ref, e->ecs.ref, e->audio.ref, &(ke_sound_module_config){ .root = e->project_dir }, &e->sounds);
    return made;
}

/** The action maps of the configuration's `input` section. */
static inline ke_result ke_sdk_default_actions(ke_sdk_engine *e)
{
    return ke_input_actions_create(e->runtime.ref, e->input.ref, e->configuration.ref, &(ke_input_actions_config){ .section = "input" }, &e->actions);
}

/** The node types. */
static inline ke_result ke_sdk_default_node_types(ke_sdk_engine *e)
{
    return ke_node_types_create(e->runtime.ref, e->ecs.ref, e->scene_tree.ref, e->actions.ref, &e->node_types);
}

/** The scene files. */
static inline ke_result ke_sdk_default_scene_files(ke_sdk_engine *e)
{
    return ke_scene_files_create(e->ecs.ref, e->node_types.ref, e->assets.ref, e->io.ref, &e->scene_files);
}

/** Every default part; copy it and replace the parts the game makes its own way. */
static const ke_sdk_engine_desc ke_sdk_engine_defaults = {
    .task_pool = ke_sdk_default_task_pool,
    .file_system = ke_sdk_default_file_system,
    .io = ke_sdk_default_io,
    .configuration = ke_sdk_default_configuration,
    .input = ke_sdk_default_input,
    .window = ke_sdk_default_window,
    .ecs = ke_sdk_default_ecs,
    .runtime = ke_sdk_default_runtime,
    .gpu_device = ke_sdk_default_gpu_device,
    .render_target = ke_sdk_default_render_target,
    .fonts = ke_sdk_default_fonts,
    .assets = ke_sdk_default_assets,
    .scene_tree = ke_sdk_default_scene_tree,
    .renderer = ke_sdk_default_renderer,
    .physics = ke_sdk_default_physics,
    .audio = ke_sdk_default_audio,
    .actions = ke_sdk_default_actions,
    .node_types = ke_sdk_default_node_types,
    .scene_files = ke_sdk_default_scene_files,
};

/** Releases the owner @p handle when it holds a part, and leaves it empty. */
#define KE_SDK_ENGINE_RELEASE(handle) do { if ((handle).ref) (handle).destroy((handle).ref); (handle).ref = NULL; } while (0)

/**
 * Releases every part of @p engine that was made, the last made first, after flushing the frame in
 * flight and unloading the runtime's modules. Safe on an engine ke_sdk_engine_create left half made.
 */
static inline void ke_sdk_engine_destroy(ke_sdk_engine *engine)
{
    if (engine->runtime.ref)
    {
        (void)engine->runtime.ref->flush_render(engine->runtime.ref);
        engine->runtime.ref->unload_modules(engine->runtime.ref);
    }
    ke_sdk_renderer *r = &engine->renderer;
    KE_SDK_ENGINE_RELEASE(engine->scene_files);
    KE_SDK_ENGINE_RELEASE(engine->node_types);
    KE_SDK_ENGINE_RELEASE(engine->actions);
    KE_SDK_ENGINE_RELEASE(engine->sounds);
    KE_SDK_ENGINE_RELEASE(engine->audio);
    KE_SDK_ENGINE_RELEASE(engine->bodies);
    KE_SDK_ENGINE_RELEASE(engine->physics);
    KE_SDK_ENGINE_RELEASE(r->labels);
    KE_SDK_ENGINE_RELEASE(r->ui);
    KE_SDK_ENGINE_RELEASE(r->tonemap);
    KE_SDK_ENGINE_RELEASE(r->forward);
    KE_SDK_ENGINE_RELEASE(r->deferred);
    KE_SDK_ENGINE_RELEASE(r->gbuffer);
    KE_SDK_ENGINE_RELEASE(r->cluster);
    KE_SDK_ENGINE_RELEASE(r->shadow);
    KE_SDK_ENGINE_RELEASE(r->frame);
    KE_SDK_ENGINE_RELEASE(r->scene);
    KE_SDK_ENGINE_RELEASE(r->camera);
    KE_SDK_ENGINE_RELEASE(r->service);
    KE_SDK_ENGINE_RELEASE(r->binder);
    KE_SDK_ENGINE_RELEASE(r->view_space);
    KE_SDK_ENGINE_RELEASE(engine->scene_tree);
    KE_SDK_ENGINE_RELEASE(engine->assets);
    KE_SDK_ENGINE_RELEASE(engine->fonts);
    KE_SDK_ENGINE_RELEASE(engine->runtime);
    KE_SDK_ENGINE_RELEASE(engine->ecs);
    KE_SDK_ENGINE_RELEASE(engine->render_target);
    KE_SDK_ENGINE_RELEASE(engine->gpu_device);
    KE_SDK_ENGINE_RELEASE(engine->window);
    KE_SDK_ENGINE_RELEASE(engine->input);
    KE_SDK_ENGINE_RELEASE(engine->configuration_source);
    KE_SDK_ENGINE_RELEASE(engine->configuration);
    KE_SDK_ENGINE_RELEASE(engine->io);
    KE_SDK_ENGINE_RELEASE(engine->file_system);
    KE_SDK_ENGINE_RELEASE(engine->task_pool);
}

/**
 * Makes every part of an engine through @p desc, in the order its fields list them, from the project
 * directory @p project beside the executable, then registers the engine's node types. On failure the
 * parts already made are released.
 * @param project [utf8] The project directory's name beside the executable; its shaders are `shaders` there.
 * @return KE_OK, KE_RESULT_NOT_FOUND when the executable's directory is unknown, or the code of the part that failed.
 */
static inline ke_result ke_sdk_engine_create(const ke_sdk_engine_desc *desc, const char *project, ke_sdk_engine *out)
{
    memset(out, 0, sizeof *out);
    if (!ke_sdk_beside_executable(out->project_dir, sizeof out->project_dir, project)
        || !ke_sdk_beside_executable(out->shader_dir, sizeof out->shader_dir, "shaders"))
        return KE_RESULT_NOT_FOUND;
    snprintf(out->default_font, sizeof out->default_font, "%s/assets/fonts/LiberationSans-Regular.ttf", out->project_dir);

    const ke_sdk_engine_part parts[] = {
        desc->task_pool, desc->file_system, desc->io, desc->configuration, desc->input, desc->window, desc->ecs,
        desc->runtime, desc->gpu_device, desc->render_target, desc->fonts, desc->assets, desc->scene_tree,
        desc->renderer, desc->physics, desc->audio, desc->actions, desc->node_types, desc->scene_files,
    };
    ke_result made = KE_OK;
    for (size_t i = 0; made == KE_OK && i < sizeof parts / sizeof parts[0]; ++i)
        made = parts[i] ? parts[i](out) : KE_RESULT_INVALID_ARGUMENT;
    for (size_t i = 0; made == KE_OK && i < KE_ENGINE_NODE_TYPE_COUNT; ++i)
    {
        ke_component_id type = KE_COMPONENT_INVALID;
        made = out->node_types.ref->register_type(out->node_types.ref, &ke_engine_node_types[i], &type);
    }
    if (made != KE_OK) ke_sdk_engine_destroy(out);
    return made;
}

/** The wall-clock time in seconds, which the loop measures each frame's step against. */
static inline double ke_sdk_engine_now(void)
{
    struct timespec t;
    timespec_get(&t, TIME_UTC);
    return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}

/**
 * Opens the scene file at @p first_scene, or the one of the project's scenes directory `project.default_scene`
 * names, and ticks until the window closes or a node asks to exit.
 * @param first_scene [utf8,optional] A `res://` path; NULL takes the project's default scene.
 * @return KE_OK, or the code of the open or the tick that failed.
 */
static inline ke_result ke_sdk_engine_run(ke_sdk_engine *engine, const char *first_scene)
{
    ke_configuration *c = ke_sdk_engine_config(engine);
    char scene[KE_SDK_ENGINE_PATH_CAPACITY];
    if (first_scene) snprintf(scene, sizeof scene, "%s", first_scene);
    else snprintf(scene, sizeof scene, "res://scenes/%s.scene.toml", c->get_string(c, "project", "default_scene", "Main"));
    ke_runtime *rt = engine->runtime.ref;
    ke_window *window = engine->window.ref;
    ke_result made = engine->scene_files.ref->open(engine->scene_files.ref, rt->commands(rt), scene, NULL);
    double previous = ke_sdk_engine_now();
    while (made == KE_OK && !window->should_close(window) && !rt->exit_requested(rt))
    {
        window->poll_events(window);
        double current = ke_sdk_engine_now();
        made = rt->tick(rt, (float)(current - previous));
        previous = current;
    }
    return made;
}

#endif
