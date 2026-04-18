#include <kernel_engine/kernel/world/world.h>
#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/components.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <string.h>

#define KE_WORLD_MAX_SYSTEMS 64

typedef struct ke_world_impl
{
    struct ke_ecs_registry *registry;
    struct ke_allocator    *allocator;

    ke_component_id transform_cid;
    ke_component_id hierarchy_cid;
    ke_component_id name_cid;
    ke_component_id script_cid;

    ke_system systems[KE_WORLD_MAX_SYSTEMS];
    size_t    system_count;

    ke_world api;
} ke_world_impl;

// ── Vtable accessors ──────────────────────────────────────────────────────────

static struct ke_ecs_registry *world_get_registry(ke_world *self)
{
    return ((ke_world_impl *)self->handle)->registry;
}

static ke_component_id world_transform_id(ke_world *self)
{
    return ((ke_world_impl *)self->handle)->transform_cid;
}

static ke_component_id world_hierarchy_id(ke_world *self)
{
    return ((ke_world_impl *)self->handle)->hierarchy_cid;
}

static ke_component_id world_name_id(ke_world *self)
{
    return ((ke_world_impl *)self->handle)->name_cid;
}

static ke_component_id world_script_id(ke_world *self)
{
    return ((ke_world_impl *)self->handle)->script_cid;
}

static ke_result world_add_system(ke_world *self, const ke_system *system)
{
    ke_world_impl *impl = (ke_world_impl *)self->handle;
    if (impl->system_count >= KE_WORLD_MAX_SYSTEMS) return KE_ERROR_OUT_OF_MEMORY;
    impl->systems[impl->system_count++] = *system;
    return KE_OK;
}

// ── Built-in: Script System ───────────────────────────────────────────────────

static void run_script_system(ke_world_impl *impl, float dt)
{
    ke_entity *entities;
    void      *data;
    size_t     count;
    ke_ecs_registry_query(impl->registry, impl->script_cid, &entities, &data, &count);

    ke_script_component *scripts = (ke_script_component *)data;
    for (size_t i = 0; i < count; i++)
    {
        ke_script_component *s = &scripts[i];
        if (!s->started)
        {
            s->started = true;
            if (s->on_start) s->on_start(entities[i]);
        }
        if (s->on_update) s->on_update(entities[i], dt);
    }
}

// ── Built-in: Transform System ────────────────────────────────────────────────
// Recursively propagates world matrices top-down through the hierarchy.

static void update_transform_recursive(ke_world_impl *impl, ke_entity entity,
                                       const ke_mat4 *parent_world)
{
    ke_transform_component *t = (ke_transform_component *)ke_ecs_component_get(
        impl->registry, entity, impl->transform_cid);
    ke_hierarchy_component *h = (ke_hierarchy_component *)ke_ecs_component_get(
        impl->registry, entity, impl->hierarchy_cid);
    if (!t) return;

    ke_mat4 local;
    ke_mat4_from_transform(&local, &t->position, &t->rotation, &t->scale);

    if (parent_world)
        ke_mat4_mul(&t->world_matrix, parent_world, &local);
    else
        t->world_matrix = local;

    if (!h) return;
    ke_entity child = h->first_child;
    while (child != KE_ENTITY_INVALID)
    {
        ke_hierarchy_component *ch = (ke_hierarchy_component *)ke_ecs_component_get(
            impl->registry, child, impl->hierarchy_cid);
        update_transform_recursive(impl, child, &t->world_matrix);
        if (!ch) break;
        child = ch->next_sibling;
    }
}

// Finds all hierarchy roots (parent == INVALID) and recurses from each.
static void update_transforms(ke_world_impl *impl)
{
    ke_entity *entities;
    void      *data;
    size_t     count;
    ke_ecs_registry_query(impl->registry, impl->hierarchy_cid, &entities, &data, &count);

    ke_hierarchy_component *hierarchies = (ke_hierarchy_component *)data;
    for (size_t i = 0; i < count; i++)
    {
        if (hierarchies[i].parent == KE_ENTITY_INVALID)
            update_transform_recursive(impl, entities[i], NULL);
    }
}

// ── Update ────────────────────────────────────────────────────────────────────

static ke_result world_update(ke_world *self, const struct ke_frame *frame)
{
    ke_world_impl *impl = (ke_world_impl *)self->handle;
    float dt = frame ? (float)frame->delta_time : 0.0f;

    run_script_system(impl, dt);
    update_transforms(impl);

    for (size_t i = 0; i < impl->system_count; i++)
    {
        ke_system *sys = &impl->systems[i];
        if (sys->update) sys->update(self, sys->handle, dt);
    }

    return KE_OK;
}

// ── Destroy ───────────────────────────────────────────────────────────────────

static void world_destroy(ke_world *self)
{
    ke_world_impl *impl = (ke_world_impl *)self->handle;
    for (size_t i = 0; i < impl->system_count; i++)
    {
        if (impl->systems[i].destroy)
            impl->systems[i].destroy(impl->systems[i].handle);
    }
    ke_ecs_registry_destroy(impl->registry);
    impl->allocator->free(impl->allocator, impl);
}

// ── Factory ───────────────────────────────────────────────────────────────────

ke_result ke_world_create(const ke_world_params *params, ke_world **out_world)
{
    if (!params || !params->allocator || !out_world) return KE_ERROR_INVALID_ARGUMENT;

    ke_world_impl *impl = (ke_world_impl *)params->allocator->alloc(
        params->allocator, sizeof(ke_world_impl), 0);
    if (!impl) return KE_ERROR_OUT_OF_MEMORY;

    memset(impl, 0, sizeof(ke_world_impl));
    impl->allocator = params->allocator;

    ke_result res = ke_ecs_registry_create(impl->allocator, &impl->registry);
    if (res != KE_OK)
    {
        impl->allocator->free(impl->allocator, impl);
        return res;
    }

    impl->transform_cid = ke_ecs_component_register(impl->registry, "ke_transform", sizeof(ke_transform_component));
    impl->hierarchy_cid = ke_ecs_component_register(impl->registry, "ke_hierarchy", sizeof(ke_hierarchy_component));
    impl->name_cid      = ke_ecs_component_register(impl->registry, "ke_name",      sizeof(ke_name_component));
    impl->script_cid    = ke_ecs_component_register(impl->registry, "ke_script",    sizeof(ke_script_component));

    impl->api.handle       = impl;
    impl->api.destroy      = world_destroy;
    impl->api.get_registry = world_get_registry;
    impl->api.update       = world_update;
    impl->api.add_system   = world_add_system;
    impl->api.transform_id = world_transform_id;
    impl->api.hierarchy_id = world_hierarchy_id;
    impl->api.name_id      = world_name_id;
    impl->api.script_id    = world_script_id;

    *out_world = &impl->api;
    return KE_OK;
}
