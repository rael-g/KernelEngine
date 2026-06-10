#include <kernel_engine/runtime/flecs/runtime_flecs.h>

#include <flecs.h>

#include <stdalign.h>
#include <stdlib.h>
#include <string.h>

// Spike-scope state. Real impl grows alongside R2+.
typedef struct registered_system {
    ke_system_params params;
    ecs_entity_t     flecs_entity;
} registered_system;

typedef struct flecs_runtime_state {
    ke_allocator      *allocator;
    ecs_world_t       *world;

    registered_system *systems;
    size_t             system_count;
    size_t             system_capacity;

    uint64_t           next_module_id;
    uint64_t           next_system_id;
} flecs_runtime_state;

typedef struct flecs_runtime_handle {
    ke_runtime           api;
    flecs_runtime_state  state;
} flecs_runtime_handle;

// ── System callback bridge ──────────────────────────────────────────────────
// flecs invokes ecs_iter_t-shaped callbacks; we translate into our vtable
// signature (ke_runtime*, user_data, dt).

static void system_trampoline(ecs_iter_t *it)
{
    registered_system *rs = (registered_system *)it->ctx;
    flecs_runtime_handle *h = (flecs_runtime_handle *)ecs_get_ctx(it->world);
    if (!h || !rs || !rs->params.execute) return;
    rs->params.execute(&h->api, rs->params.user_data, it->delta_time);
}

// ── Vtable impls ────────────────────────────────────────────────────────────

static ke_result flecs_register_module(ke_runtime *self,
                                       const ke_module_params *p,
                                       ke_module_id *out_id)
{
    if (!self || !self->handle || !p || !p->on_load) return KE_ERROR_INVALID_ARGUMENT;

    flecs_runtime_handle *h = (flecs_runtime_handle *)self->handle;
    ke_module_id id = ++h->state.next_module_id;

    // Spike: synchronous load. Dependency-ordered batching arrives with R2's
    // multi-module scenarios.
    ke_result rc = p->on_load(self, p->user_data);
    if (rc != KE_OK) return rc;

    if (out_id) *out_id = id;
    return KE_OK;
}

static ke_result flecs_register_system(ke_runtime *self,
                                       const ke_system_params *p,
                                       ke_system_id *out_id)
{
    if (!self || !self->handle || !p || !p->execute) return KE_ERROR_INVALID_ARGUMENT;
    flecs_runtime_handle *h = (flecs_runtime_handle *)self->handle;

    // Grow the system array. Real impl uses ke_array; staying inline keeps the
    // spike single-file readable.
    if (h->state.system_count == h->state.system_capacity) {
        size_t new_cap = h->state.system_capacity ? h->state.system_capacity * 2 : 4;
        registered_system *new_buf = (registered_system *)h->state.allocator->alloc(
            h->state.allocator, sizeof(registered_system) * new_cap, alignof(registered_system));
        if (!new_buf) return KE_ERROR_OUT_OF_MEMORY;
        if (h->state.systems) {
            memcpy(new_buf, h->state.systems, sizeof(registered_system) * h->state.system_count);
            h->state.allocator->free(h->state.allocator, h->state.systems);
        }
        h->state.systems = new_buf;
        h->state.system_capacity = new_cap;
    }

    registered_system *rs = &h->state.systems[h->state.system_count++];
    rs->params = *p;

    // Map phase to flecs's built-in phase entities. The spike honors only
    // Update; richer phase mapping arrives in R2 when FixedUpdate / Extract
    // get their own flecs pipeline stages.
    ecs_entity_t flecs_phase = EcsOnUpdate;
    switch (p->phase) {
        case KE_PHASE_PRE_UPDATE:  flecs_phase = EcsPreUpdate;  break;
        case KE_PHASE_UPDATE:      flecs_phase = EcsOnUpdate;   break;
        case KE_PHASE_POST_UPDATE: flecs_phase = EcsPostUpdate; break;
        default:                   flecs_phase = EcsOnUpdate;   break;
    }

    // Compose the system entity in plain C99 (no `ecs_entity()` / `ecs_ids()`
    // helper macros — flecs ships them but they resolve to compound literals
    // that clang in our C99 mode rejects). The raw API is unambiguous.
    // ecs_entity_desc_t::add is a fixed-size in-struct array, written in place.
    ecs_entity_desc_t edesc = {0};
    edesc.name   = p->name;
    edesc.add[0] = ecs_pair(EcsDependsOn, flecs_phase);

    ecs_system_desc_t desc = {0};
    desc.entity   = ecs_entity_init(h->state.world, &edesc);
    desc.callback = system_trampoline;
    desc.ctx      = rs;
    rs->flecs_entity = ecs_system_init(h->state.world, &desc);

    ke_system_id id = ++h->state.next_system_id;
    if (out_id) *out_id = id;
    return KE_OK;
}

static ke_result flecs_tick(ke_runtime *self, float dt)
{
    if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
    flecs_runtime_handle *h = (flecs_runtime_handle *)self->handle;
    return ecs_progress(h->state.world, dt) ? KE_OK : KE_OK;
}

static void flecs_destroy(ke_runtime *self)
{
    if (!self || !self->handle) return;
    flecs_runtime_handle *h = (flecs_runtime_handle *)self->handle;

    if (h->state.world) ecs_fini(h->state.world);
    if (h->state.systems) h->state.allocator->free(h->state.allocator, h->state.systems);

    ke_allocator *alloc = h->state.allocator;
    alloc->free(alloc, h);
}

// ── Factory ─────────────────────────────────────────────────────────────────

ke_result ke_runtime_flecs_create(ke_allocator *alloc,
                                  const ke_runtime_flecs_params *params,
                                  ke_runtime **out_runtime)
{
    (void)params;
    if (!alloc || !out_runtime) return KE_ERROR_INVALID_ARGUMENT;

    flecs_runtime_handle *h = (flecs_runtime_handle *)alloc->alloc(
        alloc, sizeof(flecs_runtime_handle), alignof(flecs_runtime_handle));
    if (!h) return KE_ERROR_OUT_OF_MEMORY;
    memset(h, 0, sizeof(*h));

    h->state.allocator = alloc;
    h->state.world     = ecs_init();
    if (!h->state.world) {
        alloc->free(alloc, h);
        return KE_ERROR_NOT_INITIALIZED;
    }

    // Stash the handle on the world so the trampoline can recover the runtime.
    ecs_set_ctx(h->state.world, h, NULL);

    h->api.handle          = h;
    h->api.register_module = flecs_register_module;
    h->api.register_system = flecs_register_system;
    h->api.tick            = flecs_tick;
    h->api.destroy         = flecs_destroy;

    *out_runtime = &h->api;
    return KE_OK;
}
