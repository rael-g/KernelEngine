#include <kernel_engine/kernel/runtime/runtime_create.h>
#include <kernel_engine/kernel/runtime/system_ctx.h>

#include <stdalign.h>
#include <stdlib.h>
#include <string.h>

// In-house scheduler — prototype stage of R2.5c.
//
// What's wired (validates the architectural shape end-to-end):
// - ke_system_ctx is the only door to component memory inside an execute call
// - Execute signature is (ke_system_ctx*, void*, float) — the ke_runtime* path
//   from the spike is gone
// - Sequential phase walk, one system at a time, no real waves yet
//
// What's stubbed (R2.5c-final):
// - Real R/W conflict analysis + parallel waves (Bevy algorithm)
// - enki-backed dispatcher with wave barrier
// - Defer queue + per-wave flush
// - Fixed-timestep accumulator (Glenn Fiedler)
// - Debug access-list checks in ke_system_ctx (#ifndef NDEBUG)

// ── ke_system_ctx — public type defined here (impl-private layout) ──────────

struct ke_system_ctx
{
    ke_ecs *ecs;  // borrowed; alive while the system runs
};

void *ke_system_ctx_get_mut(ke_system_ctx *ctx, ke_component_id cid, ke_entity entity)
{
    if (!ctx || !ctx->ecs) return NULL;
    return ctx->ecs->component_get(ctx->ecs, entity, cid);
}

const void *ke_system_ctx_get(ke_system_ctx *ctx, ke_component_id cid, ke_entity entity)
{
    if (!ctx || !ctx->ecs) return NULL;
    return ctx->ecs->component_get(ctx->ecs, entity, cid);
}

void ke_system_ctx_query(ke_system_ctx *ctx, ke_component_id cid,
                          ke_entity **out_entities, void **out_data, size_t *out_count)
{
    if (out_entities) *out_entities = NULL;
    if (out_data)     *out_data     = NULL;
    if (out_count)    *out_count    = 0;
    if (!ctx || !ctx->ecs) return;
    ctx->ecs->query(ctx->ecs, cid, out_entities, out_data, out_count);
}

ke_result ke_system_ctx_spawn(ke_system_ctx *ctx, ke_entity *out_entity)
{
    (void)ctx;
    (void)out_entity;
    return KE_ERROR_NOT_INITIALIZED;  // R2.5c-final wires the defer queue
}

ke_result ke_system_ctx_attach(ke_system_ctx *ctx, ke_entity entity,
                                ke_component_id cid, const void *data, size_t size)
{
    (void)ctx;
    (void)entity;
    (void)cid;
    (void)data;
    (void)size;
    return KE_ERROR_NOT_INITIALIZED;
}

ke_result ke_system_ctx_detach(ke_system_ctx *ctx, ke_entity entity, ke_component_id cid)
{
    (void)ctx;
    (void)entity;
    (void)cid;
    return KE_ERROR_NOT_INITIALIZED;
}

ke_result ke_system_ctx_despawn(ke_system_ctx *ctx, ke_entity entity)
{
    (void)ctx;
    (void)entity;
    return KE_ERROR_NOT_INITIALIZED;
}

// ── Runtime state ───────────────────────────────────────────────────────────

typedef struct registered_system
{
    ke_runtime_system_params params;
} registered_system;

typedef struct runtime_state
{
    ke_allocator *allocator;
    ke_ecs       *ecs;

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

    // Naïve wave layout for the prototype: each system is its own wave (i.e.
    // exclusive). Wave builder + R/W grouping arrive in R2.5c-final.
    // ctx lives on this stack frame — the funnel rule is honored because the
    // ctx pointer never escapes the runtime_tick scope.
    ke_system_ctx ctx;
    ctx.ecs = h->state.ecs;

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
                rs->params.execute(&ctx, rs->params.user_data, dt);
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
    // h->state.ecs is borrowed — NOT destroyed here.
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
