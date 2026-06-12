// ke_world impl — default framework aggregator. Owns ecs+runtime+scene_tree
// transferred from host on create; cascades teardown in reverse order on destroy.

// scene_tree.h is included BEFORE world_create.h so that its transitive
// `framework_export.h` define of KE_FRAMEWORK_API runs first; world_create.h's
// own fallback definition then sees the macro already defined and skips it.
#include <kernel_engine/kernel/framework/scene_tree.h>
#include <kernel_engine/framework/world_create.h>

#include <stddef.h>
#include <string.h>

typedef struct ke_world_state {
    ke_allocator             *allocator;       // borrowed
    struct ke_task_scheduler *task_scheduler;  // borrowed
    ke_ecs                   *ecs;             // owned
    ke_runtime               *runtime;         // owned
    struct ke_scene_tree     *scene_tree;      // owned (NULL allowed during C-phase transition)
    const char               *project_root;    // borrowed string
    struct ke_logger         *logger;          // borrowed
} ke_world_state;

static ke_ecs *world_ecs(struct ke_world *self) {
    ke_world_state *s = (ke_world_state *)self->handle;
    return s->ecs;
}

static ke_runtime *world_runtime(struct ke_world *self) {
    ke_world_state *s = (ke_world_state *)self->handle;
    return s->runtime;
}

static struct ke_scene_tree *world_scene_tree(struct ke_world *self) {
    ke_world_state *s = (ke_world_state *)self->handle;
    return s->scene_tree;
}

static void world_destroy(struct ke_world *self) {
    if (!self) return;
    ke_world_state *s = (ke_world_state *)self->handle;
    if (s) {
        // Reverse-create order: scene_tree → runtime → ecs.
        if (s->scene_tree) s->scene_tree->destroy(s->scene_tree);
        if (s->runtime)    s->runtime->destroy(s->runtime);
        if (s->ecs)        s->ecs->destroy(s->ecs);

        ke_allocator *a = s->allocator;
        a->free(a, s);
    }
    // self lives in the same allocation as state — already freed.
}

ke_result ke_world_create(const ke_world_params *params, ke_world **out_world) {
    if (!params || !out_world) return KE_ERROR_INVALID_ARGUMENT;
    if (!params->allocator || !params->ecs || !params->runtime) {
        return KE_ERROR_INVALID_ARGUMENT;
    }

    ke_allocator *a = params->allocator;

    // Single allocation: state + vtable contiguous. Simpler teardown.
    size_t block_size = sizeof(ke_world_state) + sizeof(ke_world);
    void *block = a->alloc(a, block_size, 8);
    if (!block) return KE_ERROR_OUT_OF_MEMORY;
    memset(block, 0, block_size);

    ke_world_state *state = (ke_world_state *)block;
    ke_world       *world = (ke_world *)((char *)block + sizeof(ke_world_state));

    state->allocator      = params->allocator;
    state->task_scheduler = params->task_scheduler;
    state->ecs            = params->ecs;
    state->runtime        = params->runtime;
    state->scene_tree     = params->scene_tree;
    state->project_root   = params->project_root;
    state->logger         = params->logger;

    world->handle     = state;
    world->ecs        = world_ecs;
    world->runtime    = world_runtime;
    world->scene_tree = world_scene_tree;
    world->destroy    = world_destroy;

    *out_world = world;
    return KE_OK;
}
