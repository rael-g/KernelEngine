#include <kernel_engine/runtime/runtime_create.h>
#include <kernel_engine/runtime/system_ctx.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>

#include <stdalign.h>
#include <stdatomic.h>
#include <stdio.h>
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

// Per-tick defer queue. Lives on the runtime; pointers from ctx route here.
// Cleared between waves after flushing. Simple variant-tagged record array;
// real impl uses a typed command buffer with per-attach payload arena.

typedef enum defer_kind {
    DEFER_SPAWN   = 1,
    DEFER_ATTACH  = 2,
    DEFER_DETACH  = 3,
    DEFER_DESPAWN = 4,
} defer_kind;

typedef struct defer_command {
    defer_kind     kind;
    ke_entity      entity;        // SPAWN: filled at flush with new id
    ke_entity     *spawn_out;     // SPAWN: writeback slot caller provided
    ke_component_id cid;          // ATTACH/DETACH
    const void    *attach_data;   // ATTACH: payload pointer (caller owns lifetime until flush)
    size_t         attach_size;
} defer_command;

typedef struct defer_queue {
    defer_command *cmds;
    size_t         count;
    size_t         capacity;
} defer_queue;

struct ke_system_ctx
{
    ke_ecs                    *ecs;          // borrowed; alive while the system runs
    const ke_component_access *access_list;  // borrowed from the system's params
    uint32_t                   access_count;
    bool                       exclusive;
    bool                       reads_snapshot; // render phase: reads route to snapshot side (§16)
    const char                *system_name;  // for diagnostics
    defer_queue               *defer;        // borrowed from the runtime
};

// Debug-only check infrastructure. Compiled in only when NDEBUG is undefined;
// release builds get zero overhead. R2.5c-final flips violations from
// log-and-continue to abort() — for now we surface failures via a counter so
// tests can assert without crashing the process.
#ifndef NDEBUG
static uint32_t s_check_failures = 0;

// Concurrency-overlap guard. The contract says no ke_ecs storage call happens
// concurrently during a wave (reads are resolved single-threaded; bodies touch
// only resolved memory). This detects a violation directly: a thread entering a
// funnel storage call while another is already inside it = the exact hazard that
// corrupted memory. Counted (atomically), never aborted, so tests can assert it.
static atomic_uint s_ecs_call_depth       = 0;
static atomic_uint s_concurrency_failures = 0;

static void ecs_call_enter(void)
{
    if (atomic_fetch_add(&s_ecs_call_depth, 1u) != 0u)
        atomic_fetch_add(&s_concurrency_failures, 1u);
}
static void ecs_call_leave(void)
{
    atomic_fetch_sub(&s_ecs_call_depth, 1u);
}

static bool access_list_contains(const ke_component_access *list, uint32_t n,
                                  ke_component_id cid, ke_access required)
{
    for (uint32_t i = 0; i < n; i++)
    {
        if (list[i].cid == cid && (list[i].access & required) == required)
            return true;
    }
    return false;
}

static void log_violation(const char *system_name, ke_component_id cid, const char *kind)
{
    fprintf(stderr,
            "[ke_system_ctx] system '%s' accessed component %u (%s) without declared "
            "access; add a ke_component_access entry to ke_runtime_system_params.access_list "
            "or set .exclusive=true if the system intentionally bypasses parallelization.\n",
            system_name ? system_name : "<unnamed>", cid, kind);
    s_check_failures++;
}
#endif

uint32_t ke_system_ctx_check_failures(void)
{
#ifndef NDEBUG
    return s_check_failures + atomic_load(&s_concurrency_failures);
#else
    return 0;
#endif
}

void ke_system_ctx_reset_check_failures(void)
{
#ifndef NDEBUG
    s_check_failures = 0;
    atomic_store(&s_concurrency_failures, 0u);
    atomic_store(&s_ecs_call_depth, 0u);
#endif
}

// ── Wave builder (Bevy-style R/W conflict grouping) ────────────────────────
//
// Walks systems in registration order, greedily packing them into the current
// wave until a conflict forces a barrier. Two systems conflict iff they share
// at least one component cid where at least one declares WRITE.

static bool systems_conflict(const ke_runtime_system_params *a,
                              const ke_runtime_system_params *b)
{
    for (uint32_t i = 0; i < a->access_count; i++)
    {
        ke_component_id  cid_a = a->access_list[i].cid;
        ke_access        acc_a = a->access_list[i].access;
        bool             a_writes = (acc_a & KE_ACCESS_WRITE) != 0;
        for (uint32_t j = 0; j < b->access_count; j++)
        {
            if (b->access_list[j].cid != cid_a) continue;
            bool b_writes = (b->access_list[j].access & KE_ACCESS_WRITE) != 0;
            if (a_writes || b_writes) return true;  // W/W or W/R conflict
        }
    }
    return false;
}

void ke_runtime_debug_compute_waves(const ke_runtime_system_params *systems,
                                     uint32_t                        system_count,
                                     uint32_t                       *out_wave_assignments,
                                     uint32_t                       *out_wave_count)
{
    if (!out_wave_count) return;
    *out_wave_count = 0;
    if (system_count == 0) return;
    if (!systems || !out_wave_assignments) return;

    uint32_t current_wave = 0;
    out_wave_assignments[0] = 0;

    // Track which systems belong to the current wave so we can check new
    // candidates against the whole set (any pair-wise conflict closes the wave).
    uint32_t wave_start = 0;  // first system index in current wave

    for (uint32_t i = 0; i < system_count; i++)
    {
        if (i == 0)
        {
            // System 0 lands in wave 0. If it's exclusive, close wave 0 so
            // the next system starts wave 1.
            out_wave_assignments[0] = 0;
            if (systems[0].exclusive)
            {
                // Already on its own; nothing else to do — next iteration
                // will see no compatible wave to join.
            }
            continue;
        }

        bool open_new = false;

        if (systems[i].exclusive)
        {
            open_new = true;
        }
        else
        {
            // Conflict with any system in the current wave?
            for (uint32_t j = wave_start; j < i; j++)
            {
                if (out_wave_assignments[j] != current_wave) continue;
                if (systems[j].exclusive)
                {
                    // Should not happen — exclusive systems sit alone — but
                    // guard anyway: conflict.
                    open_new = true;
                    break;
                }
                if (systems_conflict(&systems[i], &systems[j]))
                {
                    open_new = true;
                    break;
                }
            }
        }

        if (open_new)
        {
            current_wave++;
            wave_start = i;
        }
        out_wave_assignments[i] = current_wave;
    }

    *out_wave_count = current_wave + 1;
}

void *ke_system_ctx_get_mut(ke_system_ctx *ctx, ke_component_id cid, ke_entity entity)
{
    if (!ctx || !ctx->ecs) return NULL;
#ifndef NDEBUG
    if (!ctx->exclusive &&
        !access_list_contains(ctx->access_list, ctx->access_count, cid, KE_ACCESS_WRITE))
    {
        log_violation(ctx->system_name, cid, "MUT");
        return NULL;
    }
    ecs_call_enter();
    void *r = ctx->ecs->component_get(ctx->ecs, entity, cid);
    ecs_call_leave();
    return r;
#else
    return ctx->ecs->component_get(ctx->ecs, entity, cid);
#endif
}

const void *ke_system_ctx_get(ke_system_ctx *ctx, ke_component_id cid, ke_entity entity)
{
    if (!ctx || !ctx->ecs) return NULL;
#ifndef NDEBUG
    // Read OR write declaration covers a read access. Checked against the
    // declared (live) cid, before any snapshot routing below.
    if (!ctx->exclusive &&
        !access_list_contains(ctx->access_list, ctx->access_count, cid, KE_ACCESS_READ) &&
        !access_list_contains(ctx->access_list, ctx->access_count, cid, KE_ACCESS_WRITE))
    {
        log_violation(ctx->system_name, cid, "GET");
        return NULL;
    }
#endif
    // Render-phase reads land on the snapshot side of a double-buffered
    // component; for everything else snapshot_cid returns cid unchanged (§16).
    if (ctx->reads_snapshot && ctx->ecs->snapshot_cid)
        cid = ctx->ecs->snapshot_cid(ctx->ecs, cid);
#ifndef NDEBUG
    ecs_call_enter();
    const void *r = ctx->ecs->component_get(ctx->ecs, entity, cid);
    ecs_call_leave();
    return r;
#else
    return ctx->ecs->component_get(ctx->ecs, entity, cid);
#endif
}

void ke_system_ctx_query(ke_system_ctx *ctx, ke_component_id cid,
                          ke_entity **out_entities, void **out_data, size_t *out_count)
{
    if (out_entities) *out_entities = NULL;
    if (out_data)     *out_data     = NULL;
    if (out_count)    *out_count    = 0;
    if (!ctx || !ctx->ecs) return;
#ifndef NDEBUG
    ecs_call_enter();
    ctx->ecs->query(ctx->ecs, cid, out_entities, out_data, out_count);
    ecs_call_leave();
#else
    ctx->ecs->query(ctx->ecs, cid, out_entities, out_data, out_count);
#endif
}

// Grow defer queue capacity by doubling. Returns false on OOM.
static bool defer_reserve(defer_queue *q, size_t needed)
{
    if (needed <= q->capacity) return true;
    size_t new_cap = q->capacity ? q->capacity * 2 : 16;
    while (new_cap < needed) new_cap *= 2;
    defer_command *buf = (defer_command *)ke_alloc(
        sizeof(defer_command) * new_cap, alignof(defer_command));
    if (!buf) return false;
    if (q->cmds)
    {
        memcpy(buf, q->cmds, sizeof(defer_command) * q->count);
        ke_free(q->cmds);
    }
    q->cmds     = buf;
    q->capacity = new_cap;
    return true;
}

ke_entity ke_system_ctx_spawn(ke_system_ctx *ctx)
{
    if (!ctx || !ctx->defer) return KE_ENTITY_INVALID;
    if (!defer_reserve(ctx->defer, ctx->defer->count + 1)) return KE_ENTITY_INVALID;
    defer_command *cmd = &ctx->defer->cmds[ctx->defer->count++];
    cmd->kind      = DEFER_SPAWN;
    cmd->spawn_out = NULL;
    // Return a placeholder; actual entity id is assigned at flush time.
    // Caller must not use this value before the defer queue is flushed.
    return KE_ENTITY_INVALID;
}

bool ke_system_ctx_attach(ke_system_ctx *ctx, ke_entity entity,
                           ke_component_id cid, const void *data, size_t size)
{
    if (!ctx || !ctx->defer) return false;
    if (!defer_reserve(ctx->defer, ctx->defer->count + 1)) return false;
    defer_command *cmd = &ctx->defer->cmds[ctx->defer->count++];
    cmd->kind        = DEFER_ATTACH;
    cmd->entity      = entity;
    cmd->cid         = cid;
    cmd->attach_data = data;
    cmd->attach_size = size;
    return true;
}

bool ke_system_ctx_detach(ke_system_ctx *ctx, ke_entity entity, ke_component_id cid)
{
    if (!ctx || !ctx->defer) return false;
    if (!defer_reserve(ctx->defer, ctx->defer->count + 1)) return false;
    defer_command *cmd = &ctx->defer->cmds[ctx->defer->count++];
    cmd->kind   = DEFER_DETACH;
    cmd->entity = entity;
    cmd->cid    = cid;
    return true;
}

bool ke_system_ctx_despawn(ke_system_ctx *ctx, ke_entity entity)
{
    if (!ctx || !ctx->defer) return false;
    if (!defer_reserve(ctx->defer, ctx->defer->count + 1)) return false;
    defer_command *cmd = &ctx->defer->cmds[ctx->defer->count++];
    cmd->kind   = DEFER_DESPAWN;
    cmd->entity = entity;
    return true;
}

// Apply every queued command in registration order, route through the ke_ecs
// vtable. Increments the debug counter so tests can assert on flush volume.
static uint32_t s_defer_applied_total = 0;

static void defer_flush(defer_queue *q, ke_ecs *ecs)
{
    for (size_t i = 0; i < q->count; i++)
    {
        defer_command *cmd = &q->cmds[i];
        switch (cmd->kind)
        {
        case DEFER_SPAWN: {
            ke_entity e = ecs->entity_create(ecs);
            if (cmd->spawn_out) *cmd->spawn_out = e;
            break;
        }
        case DEFER_ATTACH: {
            void *slot = ecs->component_add(ecs, cmd->entity, cmd->cid);
            if (slot && cmd->attach_data && cmd->attach_size > 0)
                memcpy(slot, cmd->attach_data, cmd->attach_size);
            break;
        }
        case DEFER_DETACH:
            ecs->component_remove(ecs, cmd->entity, cmd->cid);
            break;
        case DEFER_DESPAWN:
            ecs->entity_destroy(ecs, cmd->entity);
            break;
        }
        s_defer_applied_total++;
    }
    q->count = 0;  // drain — capacity retained for reuse next wave
}

uint32_t ke_system_ctx_defer_applied_count(void) { return s_defer_applied_total; }
void     ke_system_ctx_reset_defer_applied(void) { s_defer_applied_total = 0; }

// ── Runtime state ───────────────────────────────────────────────────────────

typedef struct registered_system
{
    ke_runtime_system_params params;
} registered_system;

typedef struct runtime_state
{
    ke_ecs            *ecs;             // borrowed
    ke_scheduler *scheduler;  // borrowed

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

    // §16 snapshot inference runs once, on the first tick, after all systems
    // are registered: every cid a render-phase system reads is marked
    // double-buffered so the sim→render swap has a back buffer to fill.
    bool inference_done;
} runtime_state;

typedef struct runtime_handle
{
    ke_runtime    api;
    runtime_state state;
} runtime_handle;

// ── Vtable impls ────────────────────────────────────────────────────────────

static ke_module_id runtime_register_module(ke_runtime                     *self,
                                             const ke_runtime_module_params *p,
                                             ke_error                      **out_error)
{
    if (!self || !self->handle || !p || !p->on_load)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        return 0;
    }

    runtime_handle *h  = (runtime_handle *)self->handle;
    ke_module_id    id = ++h->state.next_module_id;

    if (!p->on_load(self, p->user_data, out_error)) return 0;

    return id;
}

static ke_system_id runtime_register_system(ke_runtime                     *self,
                                             const ke_runtime_system_params *p,
                                             ke_error                      **out_error)
{
    if (!self || !self->handle || !p || !p->execute)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        return 0;
    }
    runtime_handle *h = (runtime_handle *)self->handle;

    if (h->state.system_count == h->state.system_capacity)
    {
        size_t             new_cap = h->state.system_capacity ? h->state.system_capacity * 2 : 4;
        registered_system *new_buf = (registered_system *)ke_alloc(
            sizeof(registered_system) * new_cap, alignof(registered_system));
        if (!new_buf)
        {
            KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "system array allocation failed");
            return 0;
        }
        if (h->state.systems)
        {
            memcpy(new_buf, h->state.systems, sizeof(registered_system) * h->state.system_count);
            ke_free(h->state.systems);
        }
        h->state.systems         = new_buf;
        h->state.system_capacity = new_cap;
    }

    registered_system *rs = &h->state.systems[h->state.system_count++];
    rs->params            = *p;

    return ++h->state.next_system_id;
}

// Prototype limit: per-phase systems are buffered on the stack. 256 systems
// per phase covers anything sane for the spike; R2.5c-final uses ke_array.
#define KE_RUNTIME_MAX_SYSTEMS_PER_PHASE 256

// Per-task package — one per dispatched system. Holds the ke_system_ctx (so
// the worker thread reads its access metadata locally) and a private defer
// queue so concurrent systems in the same wave never race on a shared buffer.
// Flushed at the wave barrier in registration order — within a wave the
// systems are disjoint by access, so flush ordering between them is
// observably equivalent.
typedef struct task_pkg
{
    ke_system_ctx ctx;
    void        (*execute)(ke_system_ctx *, void *, float);
    void         *user_data;
    float         dt;
    defer_queue   defer;
} task_pkg;

static void task_pkg_run(void *data)
{
    task_pkg *pkg = (task_pkg *)data;
    pkg->ctx.defer = &pkg->defer;
    pkg->execute(&pkg->ctx, pkg->user_data, pkg->dt);
}

// Dispatches a wave's tasks and joins them. Run inside the ECS concurrent-read
// scope so the parallel system bodies read the world safely.
typedef struct wave_run_ctx
{
    runtime_handle *h;
    task_pkg       *pkgs;
    ke_task       **tasks;
    uint32_t       *pinned; // per-task pinned_thread (0 = load-balanced)
    uint32_t        wave_size;
} wave_run_ctx;

static void run_wave_body(void *ctx)
{
    wave_run_ctx *wc = (wave_run_ctx *)ctx;
    for (uint32_t t = 0; t < wc->wave_size; t++)
    {
        if (wc->pinned[t] > 0)
            wc->tasks[t] = wc->h->state.scheduler->dispatch_pinned(
                wc->h->state.scheduler, wc->pinned[t], task_pkg_run, &wc->pkgs[t]);
        else
            wc->tasks[t] = wc->h->state.scheduler->dispatch(
                wc->h->state.scheduler, task_pkg_run, &wc->pkgs[t]);
    }
    for (uint32_t t = 0; t < wc->wave_size; t++)
        wc->h->state.scheduler->wait(wc->h->state.scheduler, wc->tasks[t]);
}

// Filter systems by phase, compute wave layout, dispatch wave-by-wave via the
// shared task scheduler. Each system's ke_system_ctx + defer queue lives in a
// task_pkg on this stack frame; the worker thread reads them concurrently with
// any other wave system. wait_for_wave joins all workers before barrier flush.
static void runtime_run_phase(runtime_handle *h, ke_phase phase, float dt)
{
    if (h->state.system_count == 0) return;

    uint32_t phase_indices[KE_RUNTIME_MAX_SYSTEMS_PER_PHASE];
    ke_runtime_system_params phase_params[KE_RUNTIME_MAX_SYSTEMS_PER_PHASE];
    uint32_t phase_count = 0;
    for (size_t si = 0; si < h->state.system_count; si++)
    {
        registered_system *rs = &h->state.systems[si];
        if (rs->params.phase != phase) continue;
        if (!rs->params.execute) continue;
        if (phase_count >= KE_RUNTIME_MAX_SYSTEMS_PER_PHASE) break;
        phase_indices[phase_count] = (uint32_t)si;
        phase_params[phase_count]  = rs->params;
        phase_count++;
    }
    if (phase_count == 0) return;

    uint32_t wave_assignments[KE_RUNTIME_MAX_SYSTEMS_PER_PHASE];
    uint32_t wave_count = 0;
    ke_runtime_debug_compute_waves(phase_params, phase_count,
                                    wave_assignments, &wave_count);

    task_pkg pkgs[KE_RUNTIME_MAX_SYSTEMS_PER_PHASE];
    ke_task *tasks[KE_RUNTIME_MAX_SYSTEMS_PER_PHASE];
    uint32_t pinned[KE_RUNTIME_MAX_SYSTEMS_PER_PHASE];

    for (uint32_t w = 0; w < wave_count; w++)
    {
        uint32_t wave_size = 0;

        // Package the wave's systems (no ECS reads yet — just struct setup).
        for (uint32_t k = 0; k < phase_count; k++)
        {
            if (wave_assignments[k] != w) continue;
            registered_system *rs = &h->state.systems[phase_indices[k]];

            task_pkg *pkg          = &pkgs[wave_size];
            pkg->ctx.ecs           = h->state.ecs;
            pkg->ctx.access_list   = rs->params.access_list;
            pkg->ctx.access_count  = rs->params.access_count;
            pkg->ctx.exclusive     = rs->params.exclusive;
            pkg->ctx.reads_snapshot = (phase == KE_PHASE_RENDER);
            pkg->ctx.system_name   = rs->params.name;
            pkg->ctx.defer         = NULL;  // task_pkg_run binds to &pkg->defer
            pkg->execute           = rs->params.execute;
            pkg->user_data         = rs->params.user_data;
            pkg->dt                = dt;
            pkg->defer.cmds        = NULL;
            pkg->defer.count       = 0;
            pkg->defer.capacity    = 0;
            pinned[wave_size]      = rs->params.pinned_thread;
            wave_size++;
        }

        // Dispatch + join inside the ECS concurrent-read scope, so the parallel
        // system bodies read the world safely (the ECS makes reads thread-safe;
        // structural changes go to each system's defer queue, flushed below).
        wave_run_ctx wc = { h, pkgs, tasks, pinned, wave_size };
        if (h->state.ecs->concurrent_reads)
            h->state.ecs->concurrent_reads(h->state.ecs, run_wave_body, &wc);
        else
            run_wave_body(&wc);

        // Wave barrier: flush each system's deferred structural changes in
        // registration order, serially on this thread (outside the read scope).
        for (uint32_t t = 0; t < wave_size; t++)
        {
            defer_flush(&pkgs[t].defer, h->state.ecs);
            if (pkgs[t].defer.cmds)
                ke_free(pkgs[t].defer.cmds);
        }
    }
}

// Walk every render-phase system; mark each component it reads as
// double-buffered so the sim→render swap has a back buffer to fill. Tag
// components (size 0, e.g. render-resource cids) are skipped by the ecs impl.
static void runtime_infer_snapshots(runtime_handle *h)
{
    if (!h->state.ecs->set_double_buffered) return;
    for (size_t si = 0; si < h->state.system_count; si++)
    {
        registered_system *rs = &h->state.systems[si];
        if (rs->params.phase != KE_PHASE_RENDER) continue;
        for (uint32_t a = 0; a < rs->params.access_count; a++)
            h->state.ecs->set_double_buffered(h->state.ecs, rs->params.access_list[a].cid);
    }
}

static bool runtime_tick(ke_runtime *self, float dt, ke_error **out_error)
{
    if (!self || !self->handle)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        return false;
    }
    if (dt < 0.0f)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "negative dt");
        return false;
    }
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

    // Sim→render boundary (§16). One-time inference marks every component a
    // render system reads as double-buffered; the swap then freezes the sim's
    // just-written live side into the snapshot the render phase reads.
    if (!h->state.inference_done)
    {
        runtime_infer_snapshots(h);
        h->state.inference_done = true;
    }
    if (h->state.ecs->swap_snapshots)
        h->state.ecs->swap_snapshots(h->state.ecs);
    runtime_run_phase(h, KE_PHASE_RENDER, dt);

    return true;
}

static void runtime_destroy(ke_runtime *self)
{
    if (!self || !self->handle) return;
    runtime_handle *h = (runtime_handle *)self->handle;

    if (h->state.systems) ke_free(h->state.systems);
    // Per-task defer queues are stack-allocated; freed at the wave barrier.
    // h->state.ecs and h->state.scheduler are borrowed — NOT destroyed here.
    ke_free(h);
}

// ── Factory ─────────────────────────────────────────────────────────────────

ke_runtime_handle ke_runtime_create(ke_ecs                  *ecs,
                                     ke_scheduler            *scheduler,
                                     const ke_runtime_params *params,
                                     ke_error               **out_error)
{
    if (!ecs || !scheduler)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        return (ke_runtime_handle){0};
    }

    runtime_handle *h = (runtime_handle *)ke_alloc(sizeof(runtime_handle), alignof(runtime_handle));
    if (!h)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "state allocation failed");
        return (ke_runtime_handle){0};
    }
    memset(h, 0, sizeof(*h));

    h->state.ecs       = ecs;
    h->state.scheduler = scheduler;

    // Fixed-timestep config: caller-provided or default. 0 in either field
    // means "use the default" so {0} params get a sane 60Hz physics tick out
    // of the box.
    h->state.fixed_dt           = (params && params->fixed_dt           > 0.0f) ? params->fixed_dt           : (1.0f / 60.0f);
    h->state.fixed_dt_max_accum = (params && params->fixed_dt_max_accum > 0.0f) ? params->fixed_dt_max_accum : 0.25f;

    h->api.handle          = h;
    h->api.register_module = runtime_register_module;
    h->api.register_system = runtime_register_system;
    h->api.tick            = runtime_tick;

    return (ke_runtime_handle){ .ref = &h->api, .destroy = runtime_destroy };
}
