#include "pong.h"

#include <kernel_engine/assembly/default/assembly_default_create.h>
#include <kernel_engine/async/enki/async_enki_parts.h>
#include <kernel_engine/configuration/configuration_create.h>
#include <kernel_engine/configuration/toml/configuration_toml.h>
#include <kernel_engine/ecs/ecs_flecs_parts.h>
#include <kernel_engine/engine_nodes/engine_nodes_parts.h>
#include <kernel_engine/file_system/std/file_system_std_create.h>
#include <kernel_engine/framework/framework_parts.h>
#include <kernel_engine/input/default/input_default_parts.h>
#include <kernel_engine/io/std/io_std_parts.h>
#include <kernel_engine/job/enki/job_system_enki_parts.h>
#include <kernel_engine/physics/body2d/physics_body2d_parts.h>
#include <kernel_engine/physics/box2d/physics_2d_box2d_parts.h>
#include <kernel_engine/runner/headless/runner_headless_parts.h>
#include <kernel_engine/runner/runner.h>
#include <kernel_engine/schedule/schedule_parts.h>
#include <kernel_engine/scheduler/scheduler_parts.h>
#include <kernel_engine/sdk/node.h>
#include <kernel_engine/sdk/paths.h>

#include <stdio.h>
#include <stdlib.h>

enum { PATH_CAPACITY = 4096 };

typedef const ke_part *(*parts_fn)(size_t *out_count);

static pong_game game;
static int scores_seen;
static pong_score_changed last_score;

static void die_result(const char *what, ke_result result)
{
    fprintf(stderr, "%s failed with result code 0x%08x\n", what, (unsigned)result);
    exit(1);
}

static void check(const char *what, ke_result result)
{
    if (result != KE_OK) die_result(what, result);
}

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

static ke_result probe_on(ke_node_ctx *ctx, void *user_data)
{
    (void)user_data;
    while (ctx->next(ctx))
    {
        last_score = *(const pong_score_changed *)ctx->event;
        ++scores_seen;
    }
    return KE_OK;
}

static void add_parts(ke_assembly *assembly, parts_fn parts)
{
    size_t count = 0;
    const ke_part *all = parts(&count);
    for (size_t i = 0; i < count; ++i) check("add_part", assembly->add_part(assembly, &all[i]));
}

static void compose(ke_assembly *a)
{
    static const parts_fn libraries[] = {
        ke_job_system_enki_parts, ke_async_enki_parts, ke_io_std_parts, ke_input_default_parts, ke_ecs_flecs_parts,
        ke_schedule_parts, ke_scheduler_parts, ke_framework_parts, ke_engine_nodes_parts, ke_physics_2d_box2d_parts,
        ke_physics_body2d_parts, ke_runner_headless_parts,
    };
    for (size_t i = 0; i < sizeof libraries / sizeof libraries[0]; ++i) add_parts(a, libraries[i]);
    check("add_part", a->add_part(a, &pong_part));

    static const char *const instances[][3] = {
        { "job", "job_system_enki", "job" },
        { "async", "async_enki", "async" },
        { "io", "io_std", "io" },
        { "input", "input_default", NULL },
        { "world", "ecs_flecs", "ecs" },
        { "startup", "schedule", "schedule" },
        { "pre_update", "schedule", "schedule" },
        { "fixed_pre_update", "schedule", "schedule" },
        { "fixed_update", "schedule", "schedule" },
        { "fixed_post_update", "schedule", "schedule" },
        { "update", "schedule", "schedule" },
        { "post_update", "schedule", "schedule" },
        { "shutdown", "schedule", "schedule" },
        { "scheduler", "scheduler", "scheduler" },
        { "layout", "scheduler_layout", NULL },
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
        { "assets", "asset_resolver", NULL },
        { "scene_files", "scene_files", "scene_files" },
        { "runner", "runner_headless", "runner" },
    };
    for (size_t i = 0; i < sizeof instances / sizeof instances[0]; ++i)
        check("add_instance", a->add_instance(a, instances[i][0], instances[i][1], instances[i][2]));

    static const char *const cadences[][2] = {
        { "startup", "startup" },       { "every_tick", "pre_update" }, { "fixed", "fixed_pre_update" },
        { "fixed", "fixed_update" },     { "fixed", "fixed_post_update" }, { "every_tick", "update" },
        { "every_tick", "post_update" }, { "shutdown", "shutdown" },
    };
    for (size_t i = 0; i < sizeof cadences / sizeof cadences[0]; ++i) check("bind", a->bind(a, "layout", cadences[i][0], cadences[i][1]));

    static const char *const phases[] = {
        "startup", "pre_update", "fixed_pre_update", "fixed_update", "fixed_post_update", "update", "post_update", "shutdown",
    };
    for (size_t i = 1; i < sizeof phases / sizeof phases[0]; ++i) check("order", a->order(a, "layout", NULL, phases[i - 1], phases[i]));

    static const char *const hooks[][3] = {
        { "hierarchy", "post_update", "post_update" },
        { "action_evaluation", "pre_update", "pre_update" },
        { "node_systems", "pre_update", "pre_update" },
        { "node_systems", "fixed_update", "fixed_update" },
        { "node_systems", "update", "update" },
        { "node_systems", "post_update", "post_update" },
        { "bodies", "fixed_post_update", "fixed_post_update" },
        { "scene_files", "first_scene", "startup" },
    };
    for (size_t i = 0; i < sizeof hooks / sizeof hooks[0]; ++i) check("bind", a->bind(a, hooks[i][0], hooks[i][1], hooks[i][2]));
}

static void *instance_of(ke_assembly *a, const char *name, const char *contract)
{
    void *instance = NULL;
    check(name, a->get(a, name, contract, &instance));
    return instance;
}

static void spawn_probe(ke_assembly *a)
{
    ke_node_types *types = instance_of(a, "node_types", "ke_node_types");
    ke_schedule *pre_update = instance_of(a, "pre_update", "ke_schedule");
    const ke_component_id events[] = { game.score_changed };
    const ke_node_type_desc probe = { .name = "test.score_probe", KE_NODE_EVENTS(events), .on = probe_on };
    ke_component_id type = KE_COMPONENT_INVALID;
    check("register the probe", types->register_type(types, &probe, &type));
    ke_entity node = KE_ENTITY_INVALID;
    check("spawn the probe", types->spawn(types, pre_update->commands(pre_update), type, "Probe", KE_ENTITY_INVALID, NULL, 0, &node));
}

int main(void)
{
    char project_dir[PATH_CAPACITY];
    char project_file[PATH_CAPACITY + 16];
    if (!ke_sdk_beside_executable(project_dir, sizeof project_dir, "pong_headless")) die_result("finding the project", KE_RESULT_NOT_FOUND);
    snprintf(project_file, sizeof project_file, "%s/Project", project_dir);

    ke_file_system_handle files;
    check("file system", ke_file_system_std_create(project_dir, &files));
    ke_configuration_handle configuration;
    check("configuration", ke_configuration_create(&configuration));
    ke_configuration_source_handle source;
    check("configuration source", ke_configuration_toml_create(files.ref, &source));
    check("loading the project", source.ref->load(source.ref, configuration.ref, project_file));

    ke_assembly_handle assembly;
    check("assembly", ke_assembly_default_create(configuration.ref, &assembly));
    ke_assembly *a = assembly.ref;
    check("route_log", a->route_log(a, print_log, NULL));
    check("add_external", a->add_external(a, "file_system", "ke_file_system", files.ref));
    compose(a);
    check("resolve", a->resolve(a, print_failure, NULL));
    ke_result made = KE_RESULT_PENDING;
    while (made == KE_RESULT_PENDING) made = a->advance(a);
    check("advance", made);

    spawn_probe(a);
    ke_runner *runner = instance_of(a, "runner", "ke_runner");
    ke_result ran = runner->run(runner);

    assembly.destroy(assembly.ref);
    source.destroy(source.ref);
    configuration.destroy(configuration.ref);
    files.destroy(files.ref);

    check("run", ran);
    if (scores_seen == 0)
    {
        fprintf(stderr, "no goal was scored\n");
        return 1;
    }
    printf("pong headless: %d goals, last score %d-%d\n", scores_seen, (int)last_score.left, (int)last_score.right);
    return 0;
}
