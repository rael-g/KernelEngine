#include <kernel_engine/runtime/flecs/runtime_flecs.h>

#include <flecs.h>

#include <stdalign.h>
#include <stdlib.h>
#include <string.h>

// Spike-scope state. Real impl grows alongside R2+.
typedef struct registered_system {
    ke_runtime_system_params params;
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

// ── Vtable impls ────────────────────────────────────────────────────────────

static ke_result flecs_register_module(ke_runtime *self,
                                       const ke_runtime_module_params *p,
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
                                       const ke_runtime_system_params *p,
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

    // Systems are NOT registered with flecs's pipeline (FLECS_PIPELINE off in
    // future builds). Our scheduler iterates the catalog and dispatches; flecs
    // is storage-only. Phase honored in tick(); R/W metadata + parallel waves
    // arrive with the real scheduler core in R2.5c.

    ke_system_id id = ++h->state.next_system_id;
    if (out_id) *out_id = id;
    return KE_OK;
}

static ke_result flecs_tick(ke_runtime *self, float dt)
{
    if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
    flecs_runtime_handle *h = (flecs_runtime_handle *)self->handle;

    // Transitional sequential scheduler — walks phases in order, runs every
    // system whose phase matches, no parallelism yet. Replaced by the real
    // wave-dispatch scheduler in R2.5c. Tests for register/tick/destroy
    // semantics keep passing through this stub.
    static const ke_phase phase_order[] = {
        KE_PHASE_PRE_UPDATE,
        KE_PHASE_FIXED_UPDATE,
        KE_PHASE_UPDATE,
        KE_PHASE_POST_UPDATE,
        KE_PHASE_EXTRACT,
    };
    for (size_t pi = 0; pi < sizeof(phase_order) / sizeof(phase_order[0]); pi++) {
        ke_phase phase = phase_order[pi];
        for (size_t si = 0; si < h->state.system_count; si++) {
            registered_system *rs = &h->state.systems[si];
            if (rs->params.phase != phase) continue;
            if (rs->params.execute) {
                rs->params.execute(self, rs->params.user_data, dt);
            }
        }
    }
    return KE_OK;
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

    h->api.handle          = h;
    h->api.register_module = flecs_register_module;
    h->api.register_system = flecs_register_system;
    h->api.tick            = flecs_tick;
    h->api.destroy         = flecs_destroy;

    *out_runtime = &h->api;
    return KE_OK;
}
