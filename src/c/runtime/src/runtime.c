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

    // Fixed-timestep accumulator (Glenn Fiedler "Fix Your Timestep!"). dt
    // collected from tick() builds up here; FIXED_UPDATE drains it at fixed_dt
    // per pass until below threshold.
    float fixed_dt;
    float fixed_dt_max_accum;
    float fixed_accumulator;
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

// Walk every system whose phase matches and execute it with the given dt.
// Naïve wave layout for the prototype: each system is its own wave (R/W
// grouping + parallel dispatch arrive in R2.5c-final wave builder).
static void runtime_run_phase(runtime_handle *h, ke_phase phase, float dt)
{
    ke_system_ctx ctx;
    ctx.ecs = h->state.ecs;

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

static ke_result runtime_tick(ke_runtime *self, float dt)
{
    if (!self || !self->handle) return KE_ERROR_INVALID_ARGUMENT;
    if (dt < 0.0f) return KE_ERROR_INVALID_ARGUMENT;
    runtime_handle *h = (runtime_handle *)self->handle;

    runtime_run_phase(h, KE_PHASE_PRE_UPDATE, dt);

    // Fixed-timestep accumulator (Glenn Fiedler). Build up the accumulator
    // from real elapsed dt, drain it at fixed_dt per pass. The dt the system
    // sees is always the stable fixed_dt — physics integrators stay sane even
    // when the host frame rate jitters.
    h->state.fixed_accumulator += dt;
    if (h->state.fixed_accumulator > h->state.fixed_dt_max_accum)
    {
        // Spiral-of-death guard: cap the accumulator at the configured max.
        // Excess time is discarded — simulation falls behind wall clock by
        // intention rather than freezing the host with a runaway catch-up loop.
        h->state.fixed_accumulator = h->state.fixed_dt_max_accum;
    }
    while (h->state.fixed_accumulator >= h->state.fixed_dt)
    {
        runtime_run_phase(h, KE_PHASE_FIXED_UPDATE, h->state.fixed_dt);
        h->state.fixed_accumulator -= h->state.fixed_dt;
    }

    runtime_run_phase(h, KE_PHASE_UPDATE,      dt);
    runtime_run_phase(h, KE_PHASE_POST_UPDATE, dt);
    runtime_run_phase(h, KE_PHASE_EXTRACT,     dt);

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
    if (!alloc || !ecs || !out_runtime) return KE_ERROR_INVALID_ARGUMENT;

    runtime_handle *h = (runtime_handle *)alloc->alloc(
        alloc, sizeof(runtime_handle), alignof(runtime_handle));
    if (!h) return KE_ERROR_OUT_OF_MEMORY;
    memset(h, 0, sizeof(*h));

    h->state.allocator = alloc;
    h->state.ecs       = ecs;

    // Fixed-timestep config: caller-provided or default. 0 in either field
    // means "use the default" so {0} params get a sane 60Hz physics tick out
    // of the box.
    h->state.fixed_dt           = (params && params->fixed_dt           > 0.0f) ? params->fixed_dt           : (1.0f / 60.0f);
    h->state.fixed_dt_max_accum = (params && params->fixed_dt_max_accum > 0.0f) ? params->fixed_dt_max_accum : 0.25f;

    h->api.handle          = h;
    h->api.register_module = runtime_register_module;
    h->api.register_system = runtime_register_system;
    h->api.tick            = runtime_tick;
    h->api.destroy         = runtime_destroy;

    *out_runtime = &h->api;
    return KE_OK;
}
