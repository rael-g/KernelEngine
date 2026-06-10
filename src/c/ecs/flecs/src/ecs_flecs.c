#include <kernel_engine/kernel/world/ke_ecs.h>

#include <flecs.h>

#include <stdalign.h>
#include <stdlib.h>
#include <string.h>

// Storage-only flecs wrapper. The scheduler is OUR ke_runtime; this plugin
// satisfies the ke_ecs contract by delegating to flecs's archetype storage,
// query engine, and observer machinery. Pipeline/system/timer addons are
// stripped at flecs build time (R2.5b step 2) — none of those symbols are
// referenced here.
//
// Vtable methods are stubbed for R2.5b step 3 (this commit just establishes
// the plugin layout + lifecycle). Real impl arrives in R2.5c alongside the
// scheduler core, when ke_system_ctx needs to query component memory.

typedef struct ecs_flecs_state
{
    ke_allocator *allocator;
    ecs_world_t  *world;
} ecs_flecs_state;

typedef struct ecs_flecs_handle
{
    ke_ecs          api;
    ecs_flecs_state state;
} ecs_flecs_handle;

// ── Vtable stubs (real impl in R2.5c) ──────────────────────────────────────

static ke_entity ecs_flecs_entity_create(ke_ecs *self)
{
    (void)self;
    return 0;
}

static void ecs_flecs_entity_destroy(ke_ecs *self, ke_entity entity)
{
    (void)self;
    (void)entity;
}

static ke_component_id ecs_flecs_component_register(ke_ecs *self, const char *name, size_t size)
{
    (void)self;
    (void)name;
    (void)size;
    return 0;
}

static ke_result ecs_flecs_component_lookup(ke_ecs *self, const char *name, ke_component_meta *out_meta)
{
    (void)self;
    (void)name;
    (void)out_meta;
    return KE_ERROR_NOT_FOUND;
}

static void *ecs_flecs_component_add(ke_ecs *self, ke_entity entity, ke_component_id component)
{
    (void)self;
    (void)entity;
    (void)component;
    return NULL;
}

static void ecs_flecs_component_remove(ke_ecs *self, ke_entity entity, ke_component_id component)
{
    (void)self;
    (void)entity;
    (void)component;
}

static void *ecs_flecs_component_get(ke_ecs *self, ke_entity entity, ke_component_id component)
{
    (void)self;
    (void)entity;
    (void)component;
    return NULL;
}

static void ecs_flecs_query(ke_ecs *self, ke_component_id component,
                            ke_entity **out_entities, void **out_data, size_t *out_count)
{
    (void)self;
    (void)component;
    if (out_entities) *out_entities = NULL;
    if (out_data)     *out_data     = NULL;
    if (out_count)    *out_count    = 0;
}

static void ecs_flecs_destroy(ke_ecs *self)
{
    if (!self || !self->handle) return;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;

    if (h->state.world) ecs_fini(h->state.world);

    ke_allocator *alloc = h->state.allocator;
    alloc->free(alloc, h);
}

// ── Factory ─────────────────────────────────────────────────────────────────

ke_result ke_ecs_flecs_create(ke_allocator              *alloc,
                              const ke_ecs_flecs_params *params,
                              ke_ecs                   **out_ecs)
{
    (void)params;
    if (!alloc || !out_ecs) return KE_ERROR_INVALID_ARGUMENT;

    ecs_flecs_handle *h = (ecs_flecs_handle *)alloc->alloc(
        alloc, sizeof(ecs_flecs_handle), alignof(ecs_flecs_handle));
    if (!h) return KE_ERROR_OUT_OF_MEMORY;
    memset(h, 0, sizeof(*h));

    h->state.allocator = alloc;
    h->state.world     = ecs_init();
    if (!h->state.world)
    {
        alloc->free(alloc, h);
        return KE_ERROR_NOT_INITIALIZED;
    }

    h->api.handle             = h;
    h->api.entity_create      = ecs_flecs_entity_create;
    h->api.entity_destroy     = ecs_flecs_entity_destroy;
    h->api.component_register = ecs_flecs_component_register;
    h->api.component_lookup   = ecs_flecs_component_lookup;
    h->api.component_add      = ecs_flecs_component_add;
    h->api.component_remove   = ecs_flecs_component_remove;
    h->api.component_get      = ecs_flecs_component_get;
    h->api.query              = ecs_flecs_query;
    h->api.destroy            = ecs_flecs_destroy;

    *out_ecs = &h->api;
    return KE_OK;
}
