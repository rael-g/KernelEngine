#include <kernel_engine/kernel/runtime/runtime_create.h>

#include <stdalign.h>
#include <stdlib.h>
#include <string.h>

// In-house scheduler. Accepts ke_ecs* borrowed at construction; never owns
// storage. Today: sequential phase walk over the system catalog (transitional
// stub from R2.5b step 1). R2.5c replaces with Bevy-style parallel waves +
// enki dispatch + per-wave defer queue + fixed-timestep accumulator, all
// gated by ke_system_ctx (§15.8).

typedef struct registered_system
{
    ke_runtime_system_params params;
} registered_system;

typedef struct runtime_state
{
    ke_allocator *allocator;
    ke_ecs       *ecs;  // borrowed; lifetime owned by the caller

    registered_system *systems;
    size_t             system_count;
    size_t             system_capacity;

    uint64_t next_module_id;
    uint64_t next_system_id;
} runtime_state;

typedef struct runtime_handle
{
    ke_runtime    api;
    runtime_state state;
} runtime_handle;

// ── Vtable impls ────────────────────────────────────────────────────────────

static ke_result runtime_register_module(ke_runtime                     *self,
                                          const ke_runtime_module_params *p,
                                          ke_module_id                   *out_id)
{
    if (!self || !self->handle || !p || !p->on_load) return KE_ERROR_INVALID_ARGUMENT;

    runtime_handle *h  = (runtime_handle *)self->handle;
    ke_module_id    id = ++h->state.next_module_id;

    ke_result rc = p->on_load(self, p->user_data);
    if (rc != KE_OK) return rc;

    if (out_id) *out_id = id;
    return KE_OK;
}

static ke_result runtime_register_system(ke_runtime                     *self,
                                          const ke_runtime_system_params *p,
                                          ke_system_id                   *out_id)
{
    if (!self || !self->handle || !p || !p->execute) return KE_ERROR_INVALID_ARGUMENT;
    runtime_handle *h = (runtime_handle *)self->handle;

    if (h->state.system_count == h->state.system_capacity)
    {
        size_t             new_cap = h->state.system_capacity ? h->state.system_capacity * 2 : 4;
        registered_system *new_buf = (registered_system *)h->state.allocator->alloc(
            h->state.allocator, sizeof(registered_system) * new_cap, alignof(registered_system));
        if (!new_buf) return KE_ERROR_OUT_OF_MEMORY;
        if (h->state.systems)
        {
            memcpy(new_buf, h->state.systems, sizeof(registered_system) * h->state.system_count);
            h->state.allocator->free(h->state.allocator, h->state.systems);
        }
        h->state.systems         = new_buf;
        h->state.system_capacity = new_cap;
    }

    registered_system *rs = &h->state.systems[h->state.system_count++];
    rs->params            = *p;

    ke_system_id id = ++h->state.next_system_id;
    if (out_id) *out_id = id;
    return KE_OK;
}

static ke_result runtime_tick(ke_runtime *self, float dt)
{
    if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
    runtime_handle *h = (runtime_handle *)self->handle;

    static const ke_phase phase_order[] = {
        KE_PHASE_PRE_UPDATE,
        KE_PHASE_FIXED_UPDATE,
        KE_PHASE_UPDATE,
        KE_PHASE_POST_UPDATE,
        KE_PHASE_EXTRACT,
    };
    for (size_t pi = 0; pi < sizeof(phase_order) / sizeof(phase_order[0]); pi++)
    {
        ke_phase phase = phase_order[pi];
        for (size_t si = 0; si < h->state.system_count; si++)
        {
            registered_system *rs = &h->state.systems[si];
            if (rs->params.phase != phase) continue;
            if (rs->params.execute)
            {
                rs->params.execute(self, rs->params.user_data, dt);
            }
        }
    }
    return KE_OK;
}

static void runtime_destroy(ke_runtime *self)
{
    if (!self || !self->handle) return;
    runtime_handle *h = (runtime_handle *)self->handle;

    if (h->state.systems) h->state.allocator->free(h->state.allocator, h->state.systems);

    ke_allocator *alloc = h->state.allocator;
    alloc->free(alloc, h);
    // h->state.ecs is borrowed — NOT destroyed here. The caller arranges
    // ke_ecs->destroy() lifetime separately.
}

// ── Factory ─────────────────────────────────────────────────────────────────

ke_result ke_runtime_create(ke_allocator            *alloc,
                             ke_ecs                  *ecs,
                             const ke_runtime_params *params,
                             ke_runtime             **out_runtime)
{
    (void)params;
    if (!alloc || !ecs || !out_runtime) return KE_ERROR_INVALID_ARGUMENT;

    runtime_handle *h = (runtime_handle *)alloc->alloc(
        alloc, sizeof(runtime_handle), alignof(runtime_handle));
    if (!h) return KE_ERROR_OUT_OF_MEMORY;
    memset(h, 0, sizeof(*h));

    h->state.allocator = alloc;
    h->state.ecs       = ecs;

    h->api.handle          = h;
    h->api.register_module = runtime_register_module;
    h->api.register_system = runtime_register_system;
    h->api.tick            = runtime_tick;
    h->api.destroy         = runtime_destroy;

    *out_runtime = &h->api;
    return KE_OK;
}
