// ke_world impl — default framework aggregator. Owns ecs+runtime+scene_tree
// transferred from host on create; cascades teardown in reverse order on destroy.

// scene_tree.h is included BEFORE world_create.h so that its transitive
// `framework_export.h` define of KE_FRAMEWORK_API runs first; world_create.h's
// own fallback definition then sees the macro already defined and skips it.
#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/framework/components.h>
#include <kernel_engine/framework/world_create.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>
#include "components_apply.h"

#include <stddef.h>
#include <string.h>

// Component-apply registry: a tiny linear array of (cid, fn) pairs. The
// scene_loader is the only consumer today; lookups happen at scene-load time
// (not per-frame), so linear scan over the typical 6-20 registered apply
// entries is fine. If the registry grows past ~64 we can swap for a hash.
typedef struct apply_entry {
    ke_component_id        cid;
    ke_component_apply_fn  fn;
} apply_entry;

typedef struct ke_world_state {
    ke_allocator             *allocator;       // owned — created internally in ke_world_create
    struct ke_task_scheduler *task_scheduler;  // borrowed
    ke_ecs                   *ecs;             // owned
    ke_runtime               *runtime;         // owned
    struct ke_scene_tree     *scene_tree;      // owned (NULL allowed during C-phase transition)
    const char               *project_root;    // borrowed string
    struct ke_logger         *logger;          // borrowed

    apply_entry              *apply_registry;
    uint32_t                  apply_count;
    uint32_t                  apply_capacity;
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

static ke_result world_register_component_apply(struct ke_world *self,
                                                  ke_component_id cid,
                                                  ke_component_apply_fn apply,
                                                  ke_error **out_error) {
    if (!self || !self->handle || !apply) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    ke_world_state *s = (ke_world_state *)self->handle;

    // Replace-if-exists: registering the same cid twice updates the function.
    for (uint32_t i = 0; i < s->apply_count; ++i) {
        if (s->apply_registry[i].cid == cid) {
            s->apply_registry[i].fn = apply;
            return KE_OK;
        }
    }

    if (s->apply_count == s->apply_capacity) {
        uint32_t cap = s->apply_capacity ? s->apply_capacity * 2 : 16;
        apply_entry *new_buf = (apply_entry *)s->allocator->alloc(
            s->allocator, sizeof(apply_entry) * cap, 8);
        if (!new_buf) return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "apply registry allocation failed");
        if (s->apply_registry) {
            memcpy(new_buf, s->apply_registry, sizeof(apply_entry) * s->apply_count);
            s->allocator->free(s->allocator, s->apply_registry);
        }
        s->apply_registry = new_buf;
        s->apply_capacity = cap;
    }
    s->apply_registry[s->apply_count].cid = cid;
    s->apply_registry[s->apply_count].fn  = apply;
    s->apply_count++;
    return KE_OK;
}

static ke_component_apply_fn world_get_component_apply(struct ke_world *self,
                                                        ke_component_id cid) {
    if (!self || !self->handle) return NULL;
    ke_world_state *s = (ke_world_state *)self->handle;
    for (uint32_t i = 0; i < s->apply_count; ++i) {
        if (s->apply_registry[i].cid == cid) return s->apply_registry[i].fn;
    }
    return NULL;
}

static void world_destroy(struct ke_world *self) {
    if (!self) return;
    ke_world_state *s = (ke_world_state *)self->handle;
    if (s) {
        if (s->apply_registry) s->allocator->free(s->allocator, s->apply_registry);

        // ecs, runtime, scene_tree are BORROWED — caller destroys them after world->destroy().
        // "quem cria, owna": world did not create these; world must not destroy them.
        ke_allocator *a = s->allocator;
        a->free(a, s);
        a->destroy(a);
    }
    // self lives in the same allocation as state — already freed.
}

ke_result ke_world_create(const ke_world_params *params, ke_world **out_world, ke_error **out_error) {
    if (!params || !out_world) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    if (!params->ecs || !params->runtime) {
        return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "ecs and runtime are required");
    }

    ke_allocator *a = ke_allocator_malloc_create();
    if (!a) return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "allocator creation failed");

    // Single allocation: state + vtable contiguous. Simpler teardown.
    size_t block_size = sizeof(ke_world_state) + sizeof(ke_world);
    void *block = a->alloc(a, block_size, 8);
    if (!block) { a->destroy(a); return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "state allocation failed"); }
    memset(block, 0, block_size);

    ke_world_state *state = (ke_world_state *)block;
    ke_world       *world = (ke_world *)((char *)block + sizeof(ke_world_state));

    state->allocator      = a;
    state->task_scheduler = params->task_scheduler;
    state->ecs            = params->ecs;
    state->runtime        = params->runtime;
    state->scene_tree     = params->scene_tree;
    state->project_root   = params->project_root;
    state->logger         = params->logger;

    world->handle                  = state;
    world->ecs                     = world_ecs;
    world->runtime                 = world_runtime;
    world->scene_tree              = world_scene_tree;
    world->register_component_apply = world_register_component_apply;
    world->get_component_apply     = world_get_component_apply;
    world->destroy                 = world_destroy;

    // Register the framework's built-in component vocabulary with the ecs +
    // wire up each component's apply callback. component_register is
    // idempotent in spirit — scene_tree already registers transform/hierarchy/
    // name via component_lookup-first; the others are first-touch here. The
    // host pays the schema setup cost once per world; the scene_loader then
    // works out of the box for any of these components.
    ke_ecs *e = state->ecs;
    ke_component_meta meta;
    #define REG(name, type, apply_fn) do { \
        ke_component_id _cid; \
        if (e->component_lookup(e, (name), &meta, NULL) == KE_OK) { _cid = meta.cid; } \
        else { _cid = e->component_register(e, (name), sizeof(type)); } \
        world->register_component_apply(world, _cid, (apply_fn), NULL); \
    } while (0)

    REG(KE_COMPONENT_NAME_TRANSFORM,         ke_transform_component,        ke_framework_apply_transform);
    REG(KE_COMPONENT_NAME_CAMERA,            ke_camera_component,           ke_framework_apply_camera);
    REG(KE_COMPONENT_NAME_MESH,              ke_mesh_component,             ke_framework_apply_mesh);
    REG(KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, ke_directional_light_component, ke_framework_apply_directional_light);
    REG(KE_COMPONENT_NAME_POINT_LIGHT,       ke_point_light_component,      ke_framework_apply_point_light);
    REG(KE_COMPONENT_NAME_SPOT_LIGHT,        ke_spot_light_component,       ke_framework_apply_spot_light);
    #undef REG

    *out_world = world;
    return KE_OK;
}
