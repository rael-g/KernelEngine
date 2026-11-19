#ifndef KERNEL_ENGINE_SDK_ENGINE_H_
#define KERNEL_ENGINE_SDK_ENGINE_H_

#include <kernel_engine/async/async.h>
#include <kernel_engine/audio/audio.h>
#include <kernel_engine/configuration/configuration.h>
#include <kernel_engine/configuration/configuration_source.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/extraction/extraction.h>
#include <kernel_engine/file_system/file_system.h>
#include <kernel_engine/asset/asset_resolver.h>
#include <kernel_engine/framework/engine_node_types.h>
#include <kernel_engine/framework/input_actions.h>
#include <kernel_engine/framework/node_types.h>
#include <kernel_engine/framework/scene_files.h>
#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/input/input.h>
#include <kernel_engine/io/io.h>
#include <kernel_engine/job/job_system.h>
#include <kernel_engine/module/module.h>
#include <kernel_engine/physics/physics_2d.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/gpu/gpu_render_target.h>
#include <kernel_engine/schedule/schedule.h>
#include <kernel_engine/scheduler/scheduler.h>
#include <kernel_engine/sdk/paths.h>
#include <kernel_engine/text/font.h>
#include <kernel_engine/window/window.h>

#include <stdio.h>
#include <string.h>
#include <time.h>

/**
 * @file
 * An engine made of the parts a game lists, each by a function that makes it from the parts made before it,
 * knowing only their contracts: the standard schedules, the modules attached to them, and the loop.
 */

/** The bytes each path an engine keeps can hold. */
#define KE_SDK_ENGINE_PATH_CAPACITY 1024

/** The modules an engine attaches, and the completions it waits on, at most. */
#define KE_SDK_ENGINE_LIST_CAPACITY 32

/** The standard schedules, in the order the scheduler runs them, each at its cadence. */
typedef struct ke_sdk_schedules
{
    ke_schedule_handle startup;
    ke_schedule_handle pre_update;
    ke_schedule_handle fixed;
    ke_schedule_handle update;
    ke_schedule_handle shutdown;
} ke_sdk_schedules;

/** The standard sets, each in one of the standard schedules, for the systems that need no other order. */
typedef struct ke_sdk_sets
{
    ke_schedule_set_id startup;           ///< In the startup schedule.
    ke_schedule_set_id pre_update;        ///< In the pre-update schedule.
    ke_schedule_set_id fixed_pre_update;  ///< In the fixed schedule.
    ke_schedule_set_id fixed_update;      ///< In the fixed schedule, after fixed_pre_update.
    ke_schedule_set_id fixed_post_update; ///< In the fixed schedule, after fixed_update.
    ke_schedule_set_id update;            ///< In the update schedule.
    ke_schedule_set_id post_update;       ///< In the update schedule, after update.
    ke_schedule_set_id shutdown;          ///< In the shutdown schedule.
    ke_schedule_set_id render_begin;      ///< In the render schedule.
    ke_schedule_set_id render_prepare;    ///< In the render schedule, after render_begin.
    ke_schedule_set_id render_queue;      ///< In the render schedule, after render_prepare.
    ke_schedule_set_id render_submit;     ///< In the render schedule, after render_queue.
} ke_sdk_sets;

/**
 * Every part of an engine, each an owner its part function wrote, and the paths they are made from. A part
 * function reads the parts made before its own and writes its own; a part whose function is NULL is not made
 * and its owner stays empty. ke_sdk_engine_destroy releases each one whose ref is set, the last made first.
 */
typedef struct ke_sdk_engine
{
    char project_dir[KE_SDK_ENGINE_PATH_CAPACITY];
    char shader_dir[KE_SDK_ENGINE_PATH_CAPACITY];
    char default_font[KE_SDK_ENGINE_PATH_CAPACITY];
    /** Releases the parts a package of parts keeps outside these fields; NULL when there are none. */
    void (*release_extra)(struct ke_sdk_engine *engine);

    ke_job_system_handle           job_system;
    ke_async_handle                async;
    ke_file_system_handle          file_system;
    ke_io_handle                   io;
    ke_configuration_handle        configuration;
    ke_configuration_source_handle configuration_source;
    ke_input_handle                input;
    ke_window_handle               window;
    ke_ecs_handle                  ecs;
    ke_scheduler_handle            scheduler;
    ke_sdk_schedules               schedules;
    ke_sdk_sets                    sets;
    ke_gpu_device_handle           gpu_device;
    ke_gpu_render_target_handle    render_target;
    ke_font_loader_handle          fonts;
    ke_asset_resolver_handle       assets;
    ke_scene_tree_handle           scene_tree;
    ke_module_handle               hierarchy;
    ke_physics_2d_handle           physics;
    ke_module_handle               bodies;
    ke_audio_handle                audio;
    ke_module_handle               sounds;
    ke_input_actions_handle        actions;
    ke_module_handle               action_evaluation;
    ke_node_types_handle           node_types;
    ke_module_handle               node_systems;
    ke_scene_files_handle          scene_files;
    ke_ecs_handle                  render_world;
    ke_schedule_handle             render_schedule;
    ke_extraction_handle           extraction;
    ke_module_handle               extraction_history;

    /** The modules ke_sdk_engine_run attaches once every completion in pending finished; borrowed. */
    ke_module                     *modules[KE_SDK_ENGINE_LIST_CAPACITY];
    size_t                         module_count;
    /** The completions of parts not ready yet, each released by the engine. */
    ke_completion                 *pending[KE_SDK_ENGINE_LIST_CAPACITY];
    size_t                         pending_count;
} ke_sdk_engine;

/**
 * Makes one part of @p engine from the parts made before it and writes it into its field.
 * @return KE_OK, or the code of the part that failed.
 */
typedef ke_result (*ke_sdk_engine_part)(ke_sdk_engine *engine);

/**
 * Makes one schedule over the world of @p engine; ke_sdk_engine_create makes each standard schedule with it.
 * @return KE_OK, or the code of the schedule that could not be made.
 */
typedef ke_result (*ke_sdk_engine_schedule)(ke_sdk_engine *engine, ke_schedule_handle *out_schedule);

/** The function each part of an engine is made by, in the order they are made; NULL leaves the part out. */
typedef struct ke_sdk_engine_desc
{
    ke_sdk_engine_part file_system;
    ke_sdk_engine_part configuration;
    ke_sdk_engine_part job_system;
    ke_sdk_engine_part async;
    ke_sdk_engine_part io;
    ke_sdk_engine_part input;
    ke_sdk_engine_part window;
    ke_sdk_engine_part ecs;
    ke_sdk_engine_part scheduler;
    ke_sdk_engine_schedule schedule;
    ke_sdk_engine_part gpu_device;
    ke_sdk_engine_part render_target;
    ke_sdk_engine_part fonts;
    ke_sdk_engine_part assets;
    ke_sdk_engine_part scene_tree;
    ke_sdk_engine_part extraction;
    ke_sdk_engine_part render_service;
    ke_sdk_engine_part shadow;
    ke_sdk_engine_part cluster;
    ke_sdk_engine_part gbuffer;
    ke_sdk_engine_part deferred_lighting;
    ke_sdk_engine_part forward;
    ke_sdk_engine_part tonemap;
    ke_sdk_engine_part ui;
    ke_sdk_engine_part labels;
    ke_sdk_engine_part physics;
    ke_sdk_engine_part audio;
    ke_sdk_engine_part actions;
    ke_sdk_engine_part node_types;
    ke_sdk_engine_part scene_files;
} ke_sdk_engine_desc;

/** The configuration the default parts read their sections from. */
static inline ke_configuration *ke_sdk_engine_configuration(ke_sdk_engine *e) { return e->configuration.ref; }


/** The section @p section of the engine's configuration as the settings a part is created with; NULL when the engine has
 * no configuration or the section cannot be viewed, which the part refuses. */
static inline ke_settings *ke_sdk_settings(ke_sdk_engine *e, const char *section)
{
    if (!e->configuration.ref) return NULL;
    ke_settings *settings = NULL;
    if (e->configuration.ref->section(e->configuration.ref, section, &settings) != KE_OK) settings = NULL;
    return settings;
}

/** Registers the set @p name in @p schedule, after @p after when it is not NULL, written to @p out_set. */
static inline ke_result ke_sdk_set(ke_schedule *schedule, const char *name, const ke_schedule_set_id *after, ke_schedule_set_id *out_set)
{
    return schedule->register_set(schedule, &(ke_schedule_set_desc){ .name = name, .after = after, .after_count = after ? 1u : 0u }, out_set);
}

/** Makes a standard schedule with @p make and adds it to the scheduler of @p e with @p cadence. */
static inline ke_result ke_sdk_standard_schedule(ke_sdk_engine *e, ke_sdk_engine_schedule make, ke_scheduler_cadence cadence, ke_schedule_handle *out)
{
    ke_result made = make(e, out);
    if (made == KE_OK) made = e->scheduler.ref->add(e->scheduler.ref, (ke_scheduler_run_fn)out->ref->run, out->ref, cadence);
    return made;
}

/** Makes the standard schedules with @p make, in the order the scheduler of @p e ticks them, and their sets. */
static inline ke_result ke_sdk_standard_schedules(ke_sdk_engine *e, ke_sdk_engine_schedule make)
{
    ke_sdk_schedules *sc = &e->schedules;
    ke_sdk_sets *sets = &e->sets;
    ke_result made = ke_sdk_standard_schedule(e, make, KE_SCHEDULER_CADENCE_STARTUP, &sc->startup);
    if (made == KE_OK) made = ke_sdk_standard_schedule(e, make, KE_SCHEDULER_CADENCE_EVERY_TICK, &sc->pre_update);
    if (made == KE_OK) made = ke_sdk_standard_schedule(e, make, KE_SCHEDULER_CADENCE_FIXED, &sc->fixed);
    if (made == KE_OK) made = ke_sdk_standard_schedule(e, make, KE_SCHEDULER_CADENCE_EVERY_TICK, &sc->update);
    if (made == KE_OK) made = ke_sdk_standard_schedule(e, make, KE_SCHEDULER_CADENCE_SHUTDOWN, &sc->shutdown);
    if (made == KE_OK) made = ke_sdk_set(sc->startup.ref, "startup", NULL, &sets->startup);
    if (made == KE_OK) made = ke_sdk_set(sc->pre_update.ref, "pre_update", NULL, &sets->pre_update);
    if (made == KE_OK) made = ke_sdk_set(sc->fixed.ref, "fixed_pre_update", NULL, &sets->fixed_pre_update);
    if (made == KE_OK) made = ke_sdk_set(sc->fixed.ref, "fixed_update", &sets->fixed_pre_update, &sets->fixed_update);
    if (made == KE_OK) made = ke_sdk_set(sc->fixed.ref, "fixed_post_update", &sets->fixed_update, &sets->fixed_post_update);
    if (made == KE_OK) made = ke_sdk_set(sc->update.ref, "update", NULL, &sets->update);
    if (made == KE_OK) made = ke_sdk_set(sc->update.ref, "post_update", &sets->update, &sets->post_update);
    if (made == KE_OK) made = ke_sdk_set(sc->shutdown.ref, "shutdown", NULL, &sets->shutdown);
    return made;
}

/** The standard schedules of @p e and their sets, as a module attaches to them. */
static inline ke_module_targets ke_sdk_targets(ke_sdk_engine *e)
{
    return (ke_module_targets){
        .startup = e->schedules.startup.ref, .pre_update = e->schedules.pre_update.ref, .fixed = e->schedules.fixed.ref,
        .update = e->schedules.update.ref, .shutdown = e->schedules.shutdown.ref, .render = e->render_schedule.ref,
        .startup_set = e->sets.startup, .pre_update_set = e->sets.pre_update, .fixed_pre_update_set = e->sets.fixed_pre_update,
        .fixed_update_set = e->sets.fixed_update, .fixed_post_update_set = e->sets.fixed_post_update,
        .update_set = e->sets.update, .post_update_set = e->sets.post_update, .shutdown_set = e->sets.shutdown,
        .render_begin_set = e->sets.render_begin, .render_prepare_set = e->sets.render_prepare,
        .render_queue_set = e->sets.render_queue, .render_submit_set = e->sets.render_submit,
    };
}

/** Attaches @p module to the standard schedules of @p e. */
static inline ke_result ke_sdk_attach(ke_sdk_engine *e, ke_module *module)
{
    ke_module_targets targets = ke_sdk_targets(e);
    return module->attach(module, &targets);
}

/**
 * Lists @p module for ke_sdk_engine_run to attach to the standard schedules of @p e once every part is ready.
 * @return KE_OK; KE_RESULT_OUT_OF_MEMORY when the list is full.
 */
static inline ke_result ke_sdk_add_module(ke_sdk_engine *e, ke_module *module)
{
    if (e->module_count == KE_SDK_ENGINE_LIST_CAPACITY) return KE_RESULT_OUT_OF_MEMORY;
    e->modules[e->module_count++] = module;
    return KE_OK;
}

/**
 * Lists @p ready, the completion a part finishes when it is ready, for ke_sdk_engine_run to wait on; the engine
 * releases it. When the list is full, @p ready is released and the call fails.
 * @return KE_OK; KE_RESULT_OUT_OF_MEMORY when the list is full.
 */
static inline ke_result ke_sdk_await(ke_sdk_engine *e, ke_completion *ready)
{
    if (e->pending_count == KE_SDK_ENGINE_LIST_CAPACITY)
    {
        ready->release(ready);
        return KE_RESULT_OUT_OF_MEMORY;
    }
    e->pending[e->pending_count++] = ready;
    return KE_OK;
}

/** Releases the owner @p handle when it holds a part, and leaves it empty. */
#define KE_SDK_ENGINE_RELEASE(handle) do { if ((handle).ref) (handle).destroy((handle).ref); (handle).ref = NULL; } while (0)

/**
 * Releases every part of @p engine that was made, the last made first, after shutting the scheduler
 * down. Safe on an engine ke_sdk_engine_create left half made.
 */
static inline void ke_sdk_engine_destroy(ke_sdk_engine *engine)
{
    if (engine->scheduler.ref) (void)engine->scheduler.ref->shutdown(engine->scheduler.ref);
    for (size_t i = 0; i < engine->pending_count; ++i) engine->pending[i]->release(engine->pending[i]);
    engine->pending_count = 0;
    engine->module_count = 0;
    if (engine->release_extra) engine->release_extra(engine);
    engine->release_extra = NULL;
    KE_SDK_ENGINE_RELEASE(engine->extraction_history);
    KE_SDK_ENGINE_RELEASE(engine->extraction);
    KE_SDK_ENGINE_RELEASE(engine->render_schedule);
    KE_SDK_ENGINE_RELEASE(engine->render_world);
    KE_SDK_ENGINE_RELEASE(engine->scene_files);
    KE_SDK_ENGINE_RELEASE(engine->node_systems);
    KE_SDK_ENGINE_RELEASE(engine->node_types);
    KE_SDK_ENGINE_RELEASE(engine->action_evaluation);
    KE_SDK_ENGINE_RELEASE(engine->actions);
    KE_SDK_ENGINE_RELEASE(engine->sounds);
    KE_SDK_ENGINE_RELEASE(engine->audio);
    KE_SDK_ENGINE_RELEASE(engine->bodies);
    KE_SDK_ENGINE_RELEASE(engine->physics);
    KE_SDK_ENGINE_RELEASE(engine->hierarchy);
    KE_SDK_ENGINE_RELEASE(engine->scene_tree);
    KE_SDK_ENGINE_RELEASE(engine->assets);
    KE_SDK_ENGINE_RELEASE(engine->fonts);
    KE_SDK_ENGINE_RELEASE(engine->scheduler);
    KE_SDK_ENGINE_RELEASE(engine->schedules.shutdown);
    KE_SDK_ENGINE_RELEASE(engine->schedules.update);
    KE_SDK_ENGINE_RELEASE(engine->schedules.fixed);
    KE_SDK_ENGINE_RELEASE(engine->schedules.pre_update);
    KE_SDK_ENGINE_RELEASE(engine->schedules.startup);
    KE_SDK_ENGINE_RELEASE(engine->ecs);
    KE_SDK_ENGINE_RELEASE(engine->render_target);
    KE_SDK_ENGINE_RELEASE(engine->gpu_device);
    KE_SDK_ENGINE_RELEASE(engine->window);
    KE_SDK_ENGINE_RELEASE(engine->input);
    KE_SDK_ENGINE_RELEASE(engine->io);
    KE_SDK_ENGINE_RELEASE(engine->async);
    KE_SDK_ENGINE_RELEASE(engine->job_system);
    KE_SDK_ENGINE_RELEASE(engine->configuration_source);
    KE_SDK_ENGINE_RELEASE(engine->configuration);
    KE_SDK_ENGINE_RELEASE(engine->file_system);
}

/**
 * Makes every part of an engine through @p desc, in the order its fields list them, from the project
 * directory @p project beside the executable, then registers the engine's node types when the node types
 * are made. A part whose function is NULL is left out. On failure the parts already made are released.
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

    const ke_sdk_engine_part core[] = {
        desc->file_system, desc->configuration, desc->job_system, desc->async, desc->io, desc->input, desc->window, desc->ecs,
        desc->scheduler,
    };
    const ke_sdk_engine_part parts[] = {
        desc->gpu_device, desc->render_target, desc->fonts, desc->assets, desc->scene_tree, desc->extraction,
        desc->render_service, desc->shadow, desc->cluster, desc->gbuffer, desc->deferred_lighting, desc->forward,
        desc->tonemap, desc->ui, desc->labels, desc->physics, desc->audio, desc->actions, desc->node_types, desc->scene_files,
    };
    ke_result made = KE_OK;
    for (size_t i = 0; made == KE_OK && i < sizeof core / sizeof core[0]; ++i)
        if (core[i]) made = core[i](out);
    if (made == KE_OK && out->scheduler.ref && desc->schedule) made = ke_sdk_standard_schedules(out, desc->schedule);
    for (size_t i = 0; made == KE_OK && i < sizeof parts / sizeof parts[0]; ++i)
        if (parts[i]) made = parts[i](out);
    for (size_t i = 0; made == KE_OK && out->node_types.ref && i < KE_ENGINE_NODE_TYPE_COUNT; ++i)
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
 * Pumps the window's events until every completion @p engine waits on finished, releasing each as it does.
 * @return KE_OK, or the code the first failed completion finished with.
 */
static inline ke_result ke_sdk_engine_ready(ke_sdk_engine *engine)
{
    ke_result failed = KE_OK;
    while (engine->pending_count > 0 && !engine->window.ref->should_close(engine->window.ref))
    {
        engine->window.ref->poll_events(engine->window.ref);
        for (size_t i = 0; i < engine->pending_count;)
        {
            ke_completion *c = engine->pending[i];
            ke_result result = KE_OK;
            if (!c->poll(c, &result))
            {
                ++i;
                continue;
            }
            c->release(c);
            engine->pending[i] = engine->pending[--engine->pending_count];
            if (result != KE_OK && failed == KE_OK) failed = result;
        }
    }
    return failed;
}

/** Attaches every listed module of @p engine to its standard schedules, in the order they were listed. */
static inline ke_result ke_sdk_engine_attach(ke_sdk_engine *engine)
{
    ke_result made = KE_OK;
    for (size_t i = 0; made == KE_OK && i < engine->module_count; ++i) made = ke_sdk_attach(engine, engine->modules[i]);
    return made;
}

/**
 * Waits, pumping the window's events, until every listed completion finished; attaches every listed module; opens the
 * scene file at @p first_scene, or the one of the project's scenes directory `project.default_scene` names; and ticks
 * until the window closes or a node asks to exit.
 * @param first_scene [utf8,optional] A `res://` path; NULL takes the project's default scene.
 * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for an engine without a configuration, a window, a scheduler
 *         or scene files, or the code of the completion, the attach, the open or the tick that failed.
 */
static inline ke_result ke_sdk_engine_run(ke_sdk_engine *engine, const char *first_scene)
{
    if (!engine->configuration.ref || !engine->window.ref || !engine->scheduler.ref || !engine->scene_files.ref) return KE_RESULT_INVALID_ARGUMENT;
    ke_configuration *c = ke_sdk_engine_configuration(engine);
    char scene[KE_SDK_ENGINE_PATH_CAPACITY];
    if (first_scene) snprintf(scene, sizeof scene, "%s", first_scene);
    else snprintf(scene, sizeof scene, "res://scenes/%s.scene.toml", c->get_string(c, "project", "default_scene", "Main"));
    ke_scheduler *sched = engine->scheduler.ref;
    ke_window *window = engine->window.ref;
    ke_schedule *first = engine->schedules.pre_update.ref;
    ke_result made = ke_sdk_engine_ready(engine);
    if (made == KE_OK) made = ke_sdk_engine_attach(engine);
    if (made == KE_OK) made = engine->scene_files.ref->open(engine->scene_files.ref, first->commands(first), scene, NULL);
    double previous = ke_sdk_engine_now();
    while (made == KE_OK && !window->should_close(window) && !sched->exit_requested(sched))
    {
        window->poll_events(window);
        double current = ke_sdk_engine_now();
        made = sched->tick(sched, (float)(current - previous));
        previous = current;
    }
    return made;
}

#endif
