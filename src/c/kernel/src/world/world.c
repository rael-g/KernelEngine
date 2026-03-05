#include <kernel_engine/kernel/world/world.h>
#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/components.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <string.h>

#define KE_WORLD_MAX_SYSTEMS 64

typedef struct ke_world_impl
{
    struct ke_ecs_registry *registry;
    struct ke_render *renderer;
    struct ke_window *window;
    struct ke_allocator *allocator;

    // Built-in component IDs (registered at world creation)
    ke_component_id transform_cid;
    ke_component_id hierarchy_cid;
    ke_component_id name_cid;
    ke_component_id script_cid;

    // Root entity (always entity 1)
    ke_entity root_entity;

    // User-registered C systems
    ke_system systems[KE_WORLD_MAX_SYSTEMS];
    size_t system_count;

    ke_world api;
} ke_world_impl;

// ── Vtable accessors ─────────────────────────────────────────────────────────

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

static ke_entity world_get_root(ke_world *self)
{
    return ((ke_world_impl *)self->handle)->root_entity;
}

static ke_result world_add_system(ke_world *self, const ke_system *system)
{
    ke_world_impl *impl = (ke_world_impl *)self->handle;
    if (impl->system_count >= KE_WORLD_MAX_SYSTEMS) return KE_ERROR_OUT_OF_MEMORY;
    impl->systems[impl->system_count++] = *system;
    return KE_OK;
}

// ── Node creation ─────────────────────────────────────────────────────────────

static ke_entity world_create_node(ke_world *self, const char *name, ke_entity parent)
{
    ke_world_impl *impl = (ke_world_impl *)self->handle;

    ke_entity entity = ke_ecs_entity_create(impl->registry);

    // TransformComponent
    ke_transform_component *t = (ke_transform_component *)ke_ecs_component_add(
        impl->registry, entity, impl->transform_cid);
    if (t)
    {
        t->position = (ke_vec3){0.0f, 0.0f, 0.0f};
        t->rotation = (ke_quat){0.0f, 0.0f, 0.0f, 1.0f};
        t->scale    = (ke_vec3){1.0f, 1.0f, 1.0f};
        ke_mat4_identity(&t->world_matrix);
    }

    // HierarchyComponent
    ke_hierarchy_component *h = (ke_hierarchy_component *)ke_ecs_component_add(
        impl->registry, entity, impl->hierarchy_cid);
    if (h)
    {
        h->parent       = parent;
        h->first_child  = KE_ENTITY_INVALID;
        h->next_sibling = KE_ENTITY_INVALID;
        h->prev_sibling = KE_ENTITY_INVALID;
    }

    // NameComponent
    ke_name_component *n = (ke_name_component *)ke_ecs_component_add(
        impl->registry, entity, impl->name_cid);
    if (n && name)
    {
        strncpy(n->name, name, sizeof(n->name) - 1);
        n->name[sizeof(n->name) - 1] = '\0';
    }

    // Link into parent's child list (prepend)
    if (parent != KE_ENTITY_INVALID && h)
    {
        ke_hierarchy_component *ph = (ke_hierarchy_component *)ke_ecs_component_get(
            impl->registry, parent, impl->hierarchy_cid);
        if (ph)
        {
            h->next_sibling = ph->first_child;
            if (ph->first_child != KE_ENTITY_INVALID)
            {
                ke_hierarchy_component *sib = (ke_hierarchy_component *)ke_ecs_component_get(
                    impl->registry, ph->first_child, impl->hierarchy_cid);
                if (sib) sib->prev_sibling = entity;
            }
            ph->first_child = entity;
        }
    }

    return entity;
}

// ── Node destruction ──────────────────────────────────────────────────────────

static void destroy_node_recursive(ke_world_impl *impl, ke_entity entity)
{
    ke_hierarchy_component *h = (ke_hierarchy_component *)ke_ecs_component_get(
        impl->registry, entity, impl->hierarchy_cid);
    if (!h) return;

    // Destroy children first (snapshot next before destroying)
    ke_entity child = h->first_child;
    while (child != KE_ENTITY_INVALID)
    {
        ke_hierarchy_component *ch = (ke_hierarchy_component *)ke_ecs_component_get(
            impl->registry, child, impl->hierarchy_cid);
        ke_entity next = ch ? ch->next_sibling : KE_ENTITY_INVALID;
        destroy_node_recursive(impl, child);
        child = next;
    }

    // Unlink from parent's child list
    if (h->parent != KE_ENTITY_INVALID)
    {
        ke_hierarchy_component *ph = (ke_hierarchy_component *)ke_ecs_component_get(
            impl->registry, h->parent, impl->hierarchy_cid);
        if (ph && ph->first_child == entity)
            ph->first_child = h->next_sibling;

        if (h->prev_sibling != KE_ENTITY_INVALID)
        {
            ke_hierarchy_component *ps = (ke_hierarchy_component *)ke_ecs_component_get(
                impl->registry, h->prev_sibling, impl->hierarchy_cid);
            if (ps) ps->next_sibling = h->next_sibling;
        }
        if (h->next_sibling != KE_ENTITY_INVALID)
        {
            ke_hierarchy_component *ns = (ke_hierarchy_component *)ke_ecs_component_get(
                impl->registry, h->next_sibling, impl->hierarchy_cid);
            if (ns) ns->prev_sibling = h->prev_sibling;
        }
    }

    ke_ecs_entity_destroy(impl->registry, entity);
}

static ke_result world_destroy_node(ke_world *self, ke_entity entity)
{
    ke_world_impl *impl = (ke_world_impl *)self->handle;
    if (entity == KE_ENTITY_INVALID || entity == impl->root_entity)
        return KE_ERROR_INVALID_ARGUMENT;
    destroy_node_recursive(impl, entity);
    return KE_OK;
}

// ── TransformSystem ───────────────────────────────────────────────────────────

static void update_transform_recursive(ke_world_impl *impl, ke_entity entity,
                                       const ke_mat4 *parent_world)
{
    ke_transform_component *t = (ke_transform_component *)ke_ecs_component_get(
        impl->registry, entity, impl->transform_cid);
    ke_hierarchy_component *h = (ke_hierarchy_component *)ke_ecs_component_get(
        impl->registry, entity, impl->hierarchy_cid);
    if (!t || !h) return;

    ke_mat4 local;
    ke_mat4_from_transform(&local, &t->position, &t->rotation, &t->scale);

    if (parent_world)
        ke_mat4_mul(&t->world_matrix, parent_world, &local);
    else
        t->world_matrix = local;

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

// ── ScriptSystem ──────────────────────────────────────────────────────────────

static void run_script_system(ke_world_impl *impl, float dt)
{
    ke_entity *entities;
    void *data;
    size_t count;
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

// ── World update ──────────────────────────────────────────────────────────────

static ke_result world_update(ke_world *self, const struct ke_frame *frame)
{
    ke_world_impl *impl = (ke_world_impl *)self->handle;
    float dt = frame ? (float)frame->delta_time : 0.0f;

    run_script_system(impl, dt);
    update_transform_recursive(impl, impl->root_entity, NULL);

    for (size_t i = 0; i < impl->system_count; i++)
    {
        ke_system *sys = &impl->systems[i];
        if (sys->update) sys->update(self, sys->handle, dt);
    }

    return KE_OK;
}

// ── World destroy ─────────────────────────────────────────────────────────────

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

// ── World create ──────────────────────────────────────────────────────────────

ke_result ke_world_create(const ke_world_descriptor *desc, ke_world **out_world)
{
    if (!desc || !desc->allocator || !out_world) return KE_ERROR_INVALID_ARGUMENT;

    ke_world_impl *impl = (ke_world_impl *)desc->allocator->alloc(
        desc->allocator, sizeof(ke_world_impl), 0);
    if (!impl) return KE_ERROR_OUT_OF_MEMORY;

    memset(impl, 0, sizeof(ke_world_impl));
    impl->allocator = desc->allocator;
    impl->renderer  = desc->renderer;
    impl->window    = desc->window;

    ke_result res = ke_ecs_registry_create(impl->allocator, &impl->registry);
    if (res != KE_OK)
    {
        impl->allocator->free(impl->allocator, impl);
        return res;
    }

    // Register built-in components
    impl->transform_cid = ke_ecs_component_register(impl->registry, "ke_transform",
                                                      sizeof(ke_transform_component));
    impl->hierarchy_cid = ke_ecs_component_register(impl->registry, "ke_hierarchy",
                                                      sizeof(ke_hierarchy_component));
    impl->name_cid      = ke_ecs_component_register(impl->registry, "ke_name",
                                                      sizeof(ke_name_component));
    impl->script_cid    = ke_ecs_component_register(impl->registry, "ke_script",
                                                      sizeof(ke_script_component));

    // Wire vtable
    impl->api.handle       = impl;
    impl->api.destroy      = world_destroy;
    impl->api.get_registry = world_get_registry;
    impl->api.update       = world_update;
    impl->api.create_node  = world_create_node;
    impl->api.destroy_node = world_destroy_node;
    impl->api.get_root     = world_get_root;
    impl->api.transform_id = world_transform_id;
    impl->api.hierarchy_id = world_hierarchy_id;
    impl->api.name_id      = world_name_id;
    impl->api.script_id    = world_script_id;
    impl->api.add_system   = world_add_system;

    // Create root entity
    impl->root_entity = world_create_node(&impl->api, "Root", KE_ENTITY_INVALID);

    *out_world = &impl->api;
    return KE_OK;
}
