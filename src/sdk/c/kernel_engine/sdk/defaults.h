#ifndef KERNEL_ENGINE_SDK_DEFAULTS_H_
#define KERNEL_ENGINE_SDK_DEFAULTS_H_

#include <kernel_engine/sdk/engine.h>
#include <kernel_engine/audio/miniaudio/miniaudio_audio.h>
#include <kernel_engine/audio/module/sound_module.h>
#include <kernel_engine/configuration/configuration_create.h>
#include <kernel_engine/configuration/toml/configuration_toml.h>
#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/extraction/default/extraction_create.h>
#include <kernel_engine/extraction/default/extraction_history_create.h>
#include <kernel_engine/file_system/std/file_system_std_create.h>
#include <kernel_engine/framework/asset_resolver_create.h>
#include <kernel_engine/framework/engine_node_types.h>
#include <kernel_engine/framework/input_actions_create.h>
#include <kernel_engine/framework/input_actions_evaluation_create.h>
#include <kernel_engine/framework/node_types_create.h>
#include <kernel_engine/framework/node_types_systems_create.h>
#include <kernel_engine/framework/scene_hierarchy_create.h>
#include <kernel_engine/framework/scene_files_create.h>
#include <kernel_engine/framework/scene_tree_create.h>
#include <kernel_engine/input/default/input_default_create.h>
#include <kernel_engine/io/async/io_async_create.h>
#include <kernel_engine/physics/body2d/body2d_module.h>
#include <kernel_engine/physics/box2d/box2d_physics.h>
#include <kernel_engine/render/binder_grouped/resource_binder_grouped_create.h>
#include <kernel_engine/render/camera/camera_create.h>
#include <kernel_engine/render/cluster/cluster_create.h>
#include <kernel_engine/render/deferred_lighting/deferred_lighting_create.h>
#include <kernel_engine/render/forward/forward_create.h>
#include <kernel_engine/render/frame/frame_create.h>
#include <kernel_engine/render/frame/frame_systems_create.h>
#include <kernel_engine/render/gbuffer/gbuffer_create.h>
#include <kernel_engine/render/scene/label_resolve_create.h>
#include <kernel_engine/render/scene/scene_resolve_create.h>
#include <kernel_engine/render/scene/scene_resolve_systems_create.h>
#include <kernel_engine/render/service/render_service_create.h>
#include <kernel_engine/render/shadow/shadow_create.h>
#include <kernel_engine/render/tonemap/tonemap_create.h>
#include <kernel_engine/render/ui/ui_create.h>
#include <kernel_engine/render/ui/ui_systems_create.h>
#include <kernel_engine/render_graph/simple/render_graph_simple_create.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <kernel_engine/render/webgpu/gpu_render_target_webgpu_window_create.h>
#include <kernel_engine/schedule/schedule_create.h>
#include <kernel_engine/scheduler/scheduler_create.h>
#include <kernel_engine/job/enki/job_system_enki_create.h>
#include <kernel_engine/async/enki/async_enki_create.h>
#include <kernel_engine/text/stb_truetype/stb_font.h>
#include <kernel_engine/view/space/view_space_rh_create.h>
#include <kernel_engine/window/glfw/glfw_window.h>

#include <stdio.h>
#include <string.h>

/**
 * @file
 * The common implementations of every part of an engine, each made by a function configured by the project file's
 * section for its part, which a game lists in its ke_sdk_engine_desc beside its own.
 */

/**
 * The render service, the parts every pass is built on, and the passes, each pass a module the engine attaches. A
 * resource a pass hands to others is published in the frame, which a pass reading it meets with the neutral one when
 * its pass is not made.
 */
typedef struct ke_sdk_renderer
{
    ke_render_resource_binder_handle binder;
    ke_render_service_handle         service;
    ke_render_graph_handle           graph;
    ke_view_space_handle             view_space;
    ke_render_camera_handle          camera;
    ke_render_scene_resolve_handle   scene;
    ke_module_handle                 scene_systems;
    ke_render_frame_handle           frame;
    ke_module_handle                 frame_systems;
    ke_module_handle                 shadow;
    ke_module_handle                 cluster;
    ke_module_handle                 gbuffer;
    ke_module_handle                 deferred;
    ke_module_handle                 forward;
    ke_module_handle                 tonemap;
    ke_render_ui_handle              ui;
    ke_module_handle                 ui_systems;
    ke_module_handle                 labels;
    ke_render_context                context;
} ke_sdk_renderer;

/** An engine made of the default parts: the parts every engine has, and the renderer these parts make. */
typedef struct ke_sdk_default_engine
{
    ke_sdk_engine   engine;
    ke_sdk_renderer renderer;
} ke_sdk_default_engine;

/** The renderer of @p e, which must be the engine of a ke_sdk_default_engine. */
static inline ke_sdk_renderer *ke_sdk_renderer_of(ke_sdk_engine *e)
{
    return &((ke_sdk_default_engine *)e)->renderer;
}

/** Releases the passes and the render service of @p engine, the last made first. */
static inline void ke_sdk_renderer_release(ke_sdk_engine *engine)
{
    ke_sdk_renderer *r = ke_sdk_renderer_of(engine);
    KE_SDK_ENGINE_RELEASE(r->labels);
    KE_SDK_ENGINE_RELEASE(r->ui_systems);
    KE_SDK_ENGINE_RELEASE(r->ui);
    KE_SDK_ENGINE_RELEASE(r->tonemap);
    KE_SDK_ENGINE_RELEASE(r->forward);
    KE_SDK_ENGINE_RELEASE(r->deferred);
    KE_SDK_ENGINE_RELEASE(r->gbuffer);
    KE_SDK_ENGINE_RELEASE(r->cluster);
    KE_SDK_ENGINE_RELEASE(r->shadow);
    KE_SDK_ENGINE_RELEASE(r->frame_systems);
    KE_SDK_ENGINE_RELEASE(r->frame);
    KE_SDK_ENGINE_RELEASE(r->scene_systems);
    KE_SDK_ENGINE_RELEASE(r->scene);
    KE_SDK_ENGINE_RELEASE(r->camera);
    KE_SDK_ENGINE_RELEASE(r->graph);
    KE_SDK_ENGINE_RELEASE(r->service);
    KE_SDK_ENGINE_RELEASE(r->binder);
    KE_SDK_ENGINE_RELEASE(r->view_space);
}

/** A schedule over the engine's world, running on its job system. */
static inline ke_result ke_sdk_schedule(ke_sdk_engine *e, ke_schedule_handle *out)
{
    return ke_schedule_create(e->ecs.ref, e->job_system.ref, ke_sdk_settings(e, "schedule"), out);
}

/** The scheduler with the settings of `scheduler`. */
static inline ke_result ke_sdk_scheduler(ke_sdk_engine *e)
{
    return ke_scheduler_create(e->job_system.ref, e->async.ref, ke_sdk_settings(e, "scheduler"), &e->scheduler);
}

/** An enkiTS job system with its defaults: one worker per hardware thread besides the calling one. */
static inline ke_result ke_sdk_job_system_enki(ke_sdk_engine *e)
{
    return ke_job_system_enki_create(ke_sdk_settings(e, "job"), &e->job_system);
}

/** An enkiTS async system with its defaults: two workers and room for 1024 submissions from other threads. */
static inline ke_result ke_sdk_async_enki(ke_sdk_engine *e)
{
    return ke_async_enki_create(ke_sdk_settings(e, "async"), &e->async);
}

/** The operating system's files, relative to the working directory. */
static inline ke_result ke_sdk_file_system_std(ke_sdk_engine *e)
{
    return ke_file_system_std_create(".", &e->file_system);
}

/** Reads as operations of the async system. */
static inline ke_result ke_sdk_io_async(ke_sdk_engine *e)
{
    return ke_io_async_create(e->async.ref, e->file_system.ref, &e->io);
}

/** The configuration, loaded from the file Project in the project directory. */
static inline ke_result ke_sdk_configuration_toml(ke_sdk_engine *e)
{
    char project_file[KE_SDK_ENGINE_PATH_CAPACITY + 16];
    snprintf(project_file, sizeof project_file, "%s/Project", e->project_dir);
    ke_result made = ke_configuration_create(&e->configuration);
    if (made == KE_OK) made = ke_configuration_toml_create(e->io.ref, &e->configuration_source);
    if (made == KE_OK) made = e->configuration_source.ref->load(e->configuration_source.ref, e->configuration.ref, project_file);
    return made;
}

/** The input every window event reaches. */
static inline ke_result ke_sdk_input(ke_sdk_engine *e)
{
    return ke_input_create(&e->input);
}

/** A GLFW window with the settings of `runtime.window`. */
static inline ke_result ke_sdk_window_glfw(ke_sdk_engine *e)
{
    return ke_window_glfw_create(e->input.ref, ke_sdk_settings(e, "runtime.window"), &e->window);
}

/** A flecs world with the settings of `ecs`. */
static inline ke_result ke_sdk_ecs_flecs(ke_sdk_engine *e)
{
    return ke_ecs_flecs_create(ke_sdk_settings(e, "ecs"), &e->ecs);
}





/** A WebGPU device with the settings of `runtime.renderer.device`. */
static inline ke_result ke_sdk_gpu_device_webgpu(ke_sdk_engine *e)
{
    ke_completion *ready = NULL;
    ke_result made = ke_gpu_device_webgpu_create(NULL, ke_sdk_settings(e, "runtime.renderer.device"), &ready, &e->gpu_device);
    if (made == KE_OK) made = ke_sdk_await(e, ready);
    return made;
}

/** The window's swapchain, with the settings of `runtime.renderer`. */
static inline ke_result ke_sdk_render_target_webgpu_window(ke_sdk_engine *e)
{
    return ke_gpu_render_target_webgpu_window_create(e->gpu_device.ref, e->window.ref, ke_sdk_settings(e, "runtime.renderer"), &e->render_target);
}

/** stb_truetype fonts. */
static inline ke_result ke_sdk_fonts_stb(ke_sdk_engine *e)
{
    return ke_font_loader_stb_create(e->io.ref, &e->fonts);
}

/** Assets resolved under the project directory. */
static inline ke_result ke_sdk_assets(ke_sdk_engine *e)
{
    return ke_asset_resolver_create(NULL, e->fonts.ref, e->project_dir, e->io.ref, &e->assets);
}



/** The scene tree, and the module keeping its world transforms current. */
static inline ke_result ke_sdk_scene_tree(ke_sdk_engine *e)
{
    ke_result made = ke_scene_tree_create(e->ecs.ref, &e->scene_tree);
    if (made == KE_OK) made = ke_scene_hierarchy_create(e->ecs.ref, &e->hierarchy);
    if (made == KE_OK) made = ke_sdk_add_module(e, e->hierarchy.ref);
    return made;
}

/**
 * The render service, the render graph, and the camera, scene and frame every pass is built on, the frame cleared to
 * `render.clear_color`; the scene's systems and the frame's are modules of the engine. It needs the render stage, and
 * starts the renderer of the ke_sdk_default_engine @p e is the engine of, which the engine then releases.
 */
static inline ke_result ke_sdk_render_service(ke_sdk_engine *e)
{
    ke_sdk_renderer *r = ke_sdk_renderer_of(e);
    memset(r, 0, sizeof *r);
    e->release_extra = ke_sdk_renderer_release;
    ke_gpu_device *gpu = e->gpu_device.ref;
    ke_result made = ke_render_resource_binder_grouped_create(gpu, e->io.ref, e->shader_dir, &r->binder);
    if (made == KE_OK) made = ke_render_service_create(gpu, e->render_target.ref, e->io.ref, r->binder.ref, e->shader_dir, &r->service);
    if (made == KE_OK) made = ke_render_graph_simple_create(gpu, &r->graph);
    if (made == KE_OK) made = ke_view_space_rh_create(&r->view_space);
    if (made == KE_OK) made = ke_render_camera_create(r->view_space.ref, gpu, &r->camera);
    if (made == KE_OK) made = ke_render_scene_resolve_create(e->ecs.ref, e->render_world.ref, e->extraction.ref, r->service.ref, NULL, &r->scene);
    if (made == KE_OK) made = ke_render_scene_resolve_systems_create(r->scene.ref, &r->scene_systems);
    if (made == KE_OK) made = ke_sdk_add_module(e, r->scene_systems.ref);
    if (made == KE_OK) made = ke_render_frame_create(e->render_world.ref, r->graph.ref, r->service.ref, r->camera.ref, r->scene.ref,
        KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT, KE_GPU_TEXTURE_FORMAT_D32_FLOAT, ke_sdk_settings(e, "render"), &r->frame);
    if (made == KE_OK) made = ke_render_frame_systems_create(r->frame.ref, &r->frame_systems);
    if (made == KE_OK) made = ke_sdk_add_module(e, r->frame_systems.ref);
    if (made != KE_OK) return made;
    r->context = (ke_render_context){
        .ecs = e->render_world.ref, .main = e->ecs.ref, .extraction = e->extraction.ref, .service = r->service.ref, .device = gpu,
        .view_space = r->view_space.ref, .camera = r->camera.ref, .scene = r->scene.ref, .frame = r->frame.ref,
    };
    return KE_OK;
}

/** A directional shadow map with the settings of `render.shadow`. */
static inline ke_result ke_sdk_shadow(ke_sdk_engine *e)
{
    ke_sdk_renderer *r = ke_sdk_renderer_of(e);
    ke_result made = ke_render_shadow_create(&r->context, ke_sdk_settings(e, "render.shadow"), &r->shadow);
    return made == KE_OK ? ke_sdk_add_module(e, r->shadow.ref) : made;
}

/** Point and spot lights clustered on a 16 by 9 by 24 grid, 64 to a cluster. */
static inline ke_result ke_sdk_cluster(ke_sdk_engine *e)
{
    ke_sdk_renderer *r = ke_sdk_renderer_of(e);
    ke_result made = ke_render_cluster_create(&r->context, ke_sdk_settings(e, "render.cluster"), &r->cluster);
    return made == KE_OK ? ke_sdk_add_module(e, r->cluster.ref) : made;
}

/** The gbuffer the opaque meshes and sprites are drawn into. */
static inline ke_result ke_sdk_gbuffer(ke_sdk_engine *e)
{
    ke_sdk_renderer *r = ke_sdk_renderer_of(e);
    ke_result made = ke_render_gbuffer_create(&r->context, &r->gbuffer);
    return made == KE_OK ? ke_sdk_add_module(e, r->gbuffer.ref) : made;
}

/** The gbuffer lit, with the sky's image-based light, the shadow and the clustered lights there are. */
static inline ke_result ke_sdk_deferred_lighting(ke_sdk_engine *e)
{
    ke_sdk_renderer *r = ke_sdk_renderer_of(e);
    ke_result made = ke_render_deferred_lighting_create(&r->context, ke_sdk_settings(e, "render.deferred_lighting"), &r->deferred);
    return made == KE_OK ? ke_sdk_add_module(e, r->deferred.ref) : made;
}

/** The transparent meshes, lit as the deferred pass lights the opaque ones. */
static inline ke_result ke_sdk_forward(ke_sdk_engine *e)
{
    ke_sdk_renderer *r = ke_sdk_renderer_of(e);
    ke_result made = ke_render_forward_create(&r->context, ke_sdk_settings(e, "render.forward"), &r->forward);
    return made == KE_OK ? ke_sdk_add_module(e, r->forward.ref) : made;
}

/** The frame's color mapped to the screen's range. */
static inline ke_result ke_sdk_tonemap(ke_sdk_engine *e)
{
    ke_sdk_renderer *r = ke_sdk_renderer_of(e);
    ke_result made = ke_render_tonemap_create(&r->context, &r->tonemap);
    return made == KE_OK ? ke_sdk_add_module(e, r->tonemap.ref) : made;
}

/** The UI drawn over the frame. */
static inline ke_result ke_sdk_ui(ke_sdk_engine *e)
{
    ke_sdk_renderer *r = ke_sdk_renderer_of(e);
    ke_result made = ke_render_ui_create(&r->context, &r->ui);
    if (made == KE_OK) made = ke_render_ui_systems_create(r->ui.ref, &r->ui_systems);
    return made == KE_OK ? ke_sdk_add_module(e, r->ui_systems.ref) : made;
}

/** The labels' text, laid out with the project's default font, drawn by the UI. */
static inline ke_result ke_sdk_labels(ke_sdk_engine *e)
{
    ke_sdk_renderer *r = ke_sdk_renderer_of(e);
    ke_result made = ke_render_label_resolve_create(&r->context, r->ui.ref, e->assets.ref, e->default_font, &r->labels);
    return made == KE_OK ? ke_sdk_add_module(e, r->labels.ref) : made;
}

/** A Box2D world with the settings of `runtime.physics_2d`, and the module syncing bodies. */
static inline ke_result ke_sdk_physics_box2d(ke_sdk_engine *e)
{
    ke_result made = ke_physics_2d_box2d_create(e->job_system.ref, ke_sdk_settings(e, "runtime.physics_2d"), &e->physics);
    if (made == KE_OK) made = ke_physics_body2d_create(e->ecs.ref, e->physics.ref, e->scene_tree.ref, &e->bodies);
    if (made == KE_OK) made = ke_sdk_add_module(e, e->bodies.ref);
    return made;
}

/** miniaudio, and the module playing the sound components, their clips under the project directory. */
static inline ke_result ke_sdk_audio_miniaudio(ke_sdk_engine *e)
{
    ke_result made = ke_audio_miniaudio_create(e->io.ref, &e->audio);
    if (made == KE_OK) made = ke_sound_create(e->ecs.ref, e->audio.ref, e->project_dir, &e->sounds);
    if (made == KE_OK) made = ke_sdk_add_module(e, e->sounds.ref);
    return made;
}

/** The action maps of the configuration's `input` section, and the module evaluating them each tick. */
static inline ke_result ke_sdk_actions(ke_sdk_engine *e)
{
    ke_result made = ke_input_actions_create(e->configuration.ref, "input", &e->actions);
    if (made == KE_OK) made = ke_input_actions_evaluation_create(e->actions.ref, e->input.ref, &e->action_evaluation);
    if (made == KE_OK) made = ke_sdk_add_module(e, e->action_evaluation.ref);
    return made;
}

/** The node types, and the module running their behaviours. */
static inline ke_result ke_sdk_node_types(ke_sdk_engine *e)
{
    ke_result made = ke_node_types_create(e->scheduler.ref, e->ecs.ref, e->scene_tree.ref, e->actions.ref, &e->node_types);
    if (made == KE_OK) made = ke_node_types_systems_create(e->node_types.ref, &e->node_systems);
    if (made == KE_OK) made = ke_sdk_add_module(e, e->node_systems.ref);
    return made;
}

/** The scene files. */
static inline ke_result ke_sdk_scene_files(ke_sdk_engine *e)
{
    return ke_scene_files_create(e->ecs.ref, e->node_types.ref, e->assets.ref, e->io.ref, &e->scene_files);
}

/**
 * The render stage: a flecs render world, a schedule over it with the render sets, and the extraction into it from the engine's world,
 * added to the scheduler after the standard schedules; and the module keeping the previous value of every
 * interpolation.
 */
static inline ke_result ke_sdk_extraction(ke_sdk_engine *e)
{
    ke_result made = ke_ecs_flecs_create(ke_sdk_settings(e, "ecs"), &e->render_world);
    if (made == KE_OK) made = ke_schedule_create(e->render_world.ref, e->job_system.ref, ke_sdk_settings(e, "schedule"), &e->render_schedule);
    ke_sdk_sets *sets = &e->sets;
    if (made == KE_OK) made = ke_sdk_set(e->render_schedule.ref, "render_begin", NULL, &sets->render_begin);
    if (made == KE_OK) made = ke_sdk_set(e->render_schedule.ref, "render_prepare", &sets->render_begin, &sets->render_prepare);
    if (made == KE_OK) made = ke_sdk_set(e->render_schedule.ref, "render_queue", &sets->render_prepare, &sets->render_queue);
    if (made == KE_OK) made = ke_sdk_set(e->render_schedule.ref, "render_submit", &sets->render_queue, &sets->render_submit);
    if (made == KE_OK) made = ke_extraction_create(e->ecs.ref, e->render_world.ref, e->scheduler.ref, e->render_schedule.ref, &e->extraction);
    if (made == KE_OK) made = e->scheduler.ref->add(e->scheduler.ref, (ke_scheduler_run_fn)e->extraction.ref->run, e->extraction.ref, KE_SCHEDULER_CADENCE_EVERY_TICK);
    if (made == KE_OK) made = ke_extraction_history_create(e->extraction.ref, &e->extraction_history);
    if (made == KE_OK) made = ke_sdk_add_module(e, e->extraction_history.ref);
    return made;
}

#endif
