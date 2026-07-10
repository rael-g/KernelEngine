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
    DEFER_SPAWN    = 1,
    DEFER_ATTACH   = 2,
    DEFER_DETACH   = 3,
    DEFER_DESPAWN  = 4,
    DEFER_CALLBACK = 5,
} defer_kind;

typedef struct defer_command {
    defer_kind     kind;
    ke_entity      entity;        // SPAWN: filled at flush with new id
    ke_entity     *spawn_out;     // SPAWN: writeback slot caller provided
    ke_component_id cid;          // ATTACH/DETACH
    size_t         attach_offset; // ATTACH/CALLBACK: byte offset into the payload arena
    size_t         attach_size;   // ATTACH/CALLBACK: payload byte count
    ke_defer_fn    fn;            // CALLBACK: run at the barrier with arena payload
} defer_command;

// Owns a bump arena for ATTACH payloads: attach copies the caller's component
// value in immediately, so the pointer's lifetime need not survive to the wave
// barrier (scene-tree fills stack locals). Both grow-and-retain across waves.
typedef struct defer_queue {
    defer_command *cmds;
    size_t         count;
    size_t         capacity;
    unsigned char *arena;         // payload bytes
    size_t         arena_used;
    size_t         arena_capacity;
} defer_queue;

// Per-system limits for the resolved-query path.
#define KE_MAX_QUERIES_PER_SYSTEM 8
#define KE_MAX_SEGMENTS_PER_QUERY 32

struct ke_system_ctx
{
    ke_ecs                    *ecs;          // borrowed; alive while the system runs
    const ke_component_access *access_list;  // borrowed from the system's params
    uint32_t                   access_count;
    bool                       reads_snapshot; // render phase: reads route to snapshot side (§16)
    const char                *system_name;  // for diagnostics
    defer_queue               *defer;        // borrowed from the runtime

    // Resolved query views (borrowed from the registered_system). seg_storage holds
    // KE_MAX_SEGMENTS_PER_QUERY segments per query, contiguous by query index.
    const ke_ecs_segment      *seg_storage;
    const size_t              *seg_counts;
    uint32_t                   view_query_count;
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
// funnel storage call while another is already inside it. Counted (atomically),
// never aborted, so tests can assert it.
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
            "access; add a ke_component_access entry to ke_runtime_system_params.access_list.\n",
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

// Whether a system accesses cid, and (via out_writes) whether any such access is
// a write. Reads the query terms when the system declares queries, else its direct
// access list — so both declaration styles feed the same conflict check.
static bool params_accesses(const ke_runtime_system_params *p, ke_component_id cid, bool *out_writes)
{
    bool any = false, writes = false;
    if (p->queries)
        for (uint32_t q = 0; q < p->query_count; q++)
            for (uint32_t t = 0; t < p->queries[q].term_count; t++)
                if (p->queries[q].terms[t].cid == cid)
                {
                    any = true;
                    if (p->queries[q].terms[t].access & KE_ACCESS_WRITE) writes = true;
                }
    if (p->access_list)
        for (uint32_t i = 0; i < p->access_count; i++)
            if (p->access_list[i].cid == cid)
            {
                any = true;
                if (p->access_list[i].access & KE_ACCESS_WRITE) writes = true;
            }
    if (out_writes) *out_writes = writes;
    return any;
}

static bool conflict_on_term(const ke_runtime_system_params *b, ke_component_id cid, bool a_writes)
{
    bool b_writes = false;
    return params_accesses(b, cid, &b_writes) && (a_writes || b_writes);
}

static bool systems_conflict(const ke_runtime_system_params *a,
                              const ke_runtime_system_params *b)
{
    if (a->queries)
        for (uint32_t q = 0; q < a->query_count; q++)
            for (uint32_t t = 0; t < a->queries[q].term_count; t++)
            {
                bool a_writes = (a->queries[q].terms[t].access & KE_ACCESS_WRITE) != 0;
                if (conflict_on_term(b, a->queries[q].terms[t].cid, a_writes)) return true;
            }
    if (a->access_list)
        for (uint32_t i = 0; i < a->access_count; i++)
        {
            bool a_writes = (a->access_list[i].access & KE_ACCESS_WRITE) != 0;
            if (conflict_on_term(b, a->access_list[i].cid, a_writes)) return true;
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
            out_wave_assignments[0] = 0;
            continue;
        }

        // Conflict with any system in the current wave? Any pair-wise
        // read/write conflict closes the wave and opens a new one.
        bool open_new = false;
        for (uint32_t j = wave_start; j < i; j++)
        {
            if (out_wave_assignments[j] != current_wave) continue;
            if (systems_conflict(&systems[i], &systems[j]))
            {
                open_new = true;
                break;
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
    if (!access_list_contains(ctx->access_list, ctx->access_count, cid, KE_ACCESS_WRITE))
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
    if (!access_list_contains(ctx->access_list, ctx->access_count, cid, KE_ACCESS_READ) &&
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

const ke_ecs_segment *ke_system_ctx_view(ke_system_ctx *ctx, uint32_t query_index, size_t *out_count)
{
    if (out_count) *out_count = 0;
    if (!ctx || !ctx->seg_storage || query_index >= ctx->view_query_count) return NULL;
    if (out_count) *out_count = ctx->seg_counts[query_index];
    return &ctx->seg_storage[(size_t)query_index * KE_MAX_SEGMENTS_PER_QUERY];
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

// Grow the payload arena and copy the given bytes in, returning the byte offset
// where they landed (SIZE_MAX on OOM). Offsets survive arena reallocation; the
// pointer is resolved at flush as q->arena + offset.
static size_t defer_arena_push(defer_queue *q, const void *data, size_t size)
{
    if (size == 0) return 0;
    if (q->arena_used + size > q->arena_capacity)
    {
        size_t new_cap = q->arena_capacity ? q->arena_capacity * 2 : 256;
        while (new_cap < q->arena_used + size) new_cap *= 2;
        unsigned char *buf = (unsigned char *)ke_alloc(new_cap, 16);
        if (!buf) return (size_t)-1;
        if (q->arena)
        {
            memcpy(buf, q->arena, q->arena_used);
            ke_free(q->arena);
        }
        q->arena          = buf;
        q->arena_capacity = new_cap;
    }
    size_t offset = q->arena_used;
    if (data) memcpy(q->arena + offset, data, size);
    q->arena_used += size;
    return offset;
}

ke_entity ke_system_ctx_reserve(ke_system_ctx *ctx)
{
    if (!ctx || !ctx->ecs || !ctx->ecs->entity_reserve) return KE_ENTITY_INVALID;
    return ctx->ecs->entity_reserve(ctx->ecs);
}

bool ke_system_ctx_defer(ke_system_ctx *ctx, ke_defer_fn fn,
                          const void *user, size_t user_size)
{
    if (!ctx || !ctx->defer || !fn) return false;
    size_t offset = defer_arena_push(ctx->defer, user, user_size);
    if (offset == (size_t)-1) return false;
    if (!defer_reserve(ctx->defer, ctx->defer->count + 1)) return false;
    defer_command *cmd = &ctx->defer->cmds[ctx->defer->count++];
    cmd->kind          = DEFER_CALLBACK;
    cmd->fn            = fn;
    cmd->attach_offset = offset;
    cmd->attach_size   = user_size;
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
    size_t offset = defer_arena_push(ctx->defer, data, size);
    if (offset == (size_t)-1) return false;
    if (!defer_reserve(ctx->defer, ctx->defer->count + 1)) return false;
    defer_command *cmd = &ctx->defer->cmds[ctx->defer->count++];
    cmd->kind          = DEFER_ATTACH;
    cmd->entity        = entity;
    cmd->cid           = cid;
    cmd->attach_offset = offset;
    cmd->attach_size   = size;
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
            if (slot && cmd->attach_size > 0)
                memcpy(slot, q->arena + cmd->attach_offset, cmd->attach_size);
            break;
        }
        case DEFER_DETACH:
            ecs->component_remove(ecs, cmd->entity, cmd->cid);
            break;
        case DEFER_DESPAWN:
            ecs->entity_destroy(ecs, cmd->entity);
            break;
        case DEFER_CALLBACK:
            if (cmd->fn) cmd->fn(ecs, q->arena + cmd->attach_offset);
            break;
        }
        s_defer_applied_total++;
    }
    q->count      = 0;  // drain — capacity retained for reuse next wave
    q->arena_used = 0;  // payload arena rewinds; capacity retained too
}

uint32_t ke_system_ctx_defer_applied_count(void) { return s_defer_applied_total; }
void     ke_system_ctx_reset_defer_applied(void) { s_defer_applied_total = 0; }

// ── Runtime state ───────────────────────────────────────────────────────────

typedef struct registered_system
{
    ke_runtime_system_params params;

    // Resolved-query state. The caller's query decls are copied at registration
    // (its pointer's lifetime is not ours); the union of their terms becomes the
    // derived access list (params.access_list is repointed to it), and seg_storage
    // holds the segments each frame's resolve fills (read by this system's body).
    //
    // The ECS-side queries are registered later, on the first tick that sees this
    // system: a render system's queries must resolve against the SNAPSHOT cids,
    // and those exist only once snapshot inference has run over every registered
    // system's access list.
    ke_query_decl   query_decls[KE_MAX_QUERIES_PER_SYSTEM];
    ke_query_id     query_ids[KE_MAX_QUERIES_PER_SYSTEM];
    uint32_t        query_count;
    ke_ecs_segment *seg_storage; // KE_MAX_QUERIES_PER_SYSTEM * KE_MAX_SEGMENTS_PER_QUERY
    size_t          seg_counts[KE_MAX_QUERIES_PER_SYSTEM];
    ke_component_access derived_access[KE_MAX_QUERIES_PER_SYSTEM * KE_QUERY_MAX_TERMS];
    uint32_t            derived_access_count;
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

    // §16 snapshot preparation cursor: systems in [0, systems_prepared) have had
    // their render-phase cids marked double-buffered and their ECS queries
    // registered. Runs at the top of a tick, never at registration, because
    // inference must see every system's access list before any render system's
    // queries are bound to a snapshot cid.
    //
    // A render system registered after a tick has already run will not retroactively
    // re-point an earlier system's queries at a cid it newly marks double-buffered.
    // Every module registers its systems before the first tick, so this holds.
    size_t systems_prepared;
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

    registered_system *rs   = &h->state.systems[h->state.system_count++];
    rs->params              = *p;
    rs->query_count         = 0;
    rs->seg_storage         = NULL;
    rs->derived_access_count = 0;

    if (p->queries && p->query_count > 0)
    {
        uint32_t qn = p->query_count;
        if (qn > KE_MAX_QUERIES_PER_SYSTEM) qn = KE_MAX_QUERIES_PER_SYSTEM;

        for (uint32_t q = 0; q < qn; q++)
        {
            const ke_query_decl *qd = &p->queries[q];
            uint32_t tn = qd->term_count;
            if (tn > KE_QUERY_MAX_TERMS) tn = KE_QUERY_MAX_TERMS;

            // Copy the decl: the caller's queries pointer is dropped below.
            rs->query_decls[q]            = *qd;
            rs->query_decls[q].term_count = tn;
            rs->query_ids[q]              = KE_QUERY_INVALID; // bound on the first tick

            for (uint32_t t = 0; t < tn; t++)
            {
                // Fold into the derived access list: dedup the cid, OR the modes.
                // Always the LIVE cid — the wave-builder orders on the caller's
                // declared vocabulary, not on the snapshot the reads resolve to.
                bool found = false;
                for (uint32_t d = 0; d < rs->derived_access_count; d++)
                {
                    if (rs->derived_access[d].cid == qd->terms[t].cid)
                    {
                        rs->derived_access[d].access |= qd->terms[t].access;
                        found = true;
                        break;
                    }
                }
                if (!found && rs->derived_access_count < KE_MAX_QUERIES_PER_SYSTEM * KE_QUERY_MAX_TERMS)
                {
                    rs->derived_access[rs->derived_access_count].cid    = qd->terms[t].cid;
                    rs->derived_access[rs->derived_access_count].access = qd->terms[t].access;
                    rs->derived_access_count++;
                }
            }
        }
        rs->query_count = qn;

        // Fold any direct access entries (ordering-only tags a query doesn't read,
        // e.g. render-resource markers) into the derived list so the wave-builder
        // sees them too.
        for (uint32_t i = 0; i < p->access_count; i++)
        {
            bool found = false;
            for (uint32_t d = 0; d < rs->derived_access_count; d++)
                if (rs->derived_access[d].cid == p->access_list[i].cid)
                {
                    rs->derived_access[d].access |= p->access_list[i].access;
                    found = true;
                    break;
                }
            if (!found && rs->derived_access_count < KE_MAX_QUERIES_PER_SYSTEM * KE_QUERY_MAX_TERMS)
            {
                rs->derived_access[rs->derived_access_count] = p->access_list[i];
                rs->derived_access_count++;
            }
        }

        // The wave-builder and the funnel guard read this derived list. Drop the
        // caller's queries pointer — its lifetime is not ours; the copied decls,
        // resolved query ids and segment storage are owned by this registered_system.
        rs->params.access_list  = rs->derived_access;
        rs->params.access_count = rs->derived_access_count;
        rs->params.queries      = NULL;
        rs->params.query_count  = 0;

        rs->seg_storage = (ke_ecs_segment *)ke_alloc(
            sizeof(ke_ecs_segment) * KE_MAX_QUERIES_PER_SYSTEM * KE_MAX_SEGMENTS_PER_QUERY,
            alignof(ke_ecs_segment));
        if (!rs->seg_storage)
        {
            h->state.system_count--;
            KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "query segment storage allocation failed");
            return 0;
        }
    }

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
            pkg->ctx.reads_snapshot = (phase == KE_PHASE_RENDER);
            pkg->ctx.system_name   = rs->params.name;
            pkg->ctx.defer         = NULL;  // task_pkg_run binds to &pkg->defer

            // Resolve this system's queries here — single-threaded, before the wave
            // dispatches — so the parallel body reads only the resolved segments and
            // never touches the storage concurrently.
            if (rs->query_count > 0 && rs->seg_storage && h->state.ecs->query_resolve)
            {
                for (uint32_t q = 0; q < rs->query_count; q++)
                {
                    ke_ecs_segment *dst = &rs->seg_storage[(size_t)q * KE_MAX_SEGMENTS_PER_QUERY];
                    size_t          cnt = 0;
                    h->state.ecs->query_resolve(h->state.ecs, rs->query_ids[q], dst,
                                                KE_MAX_SEGMENTS_PER_QUERY, &cnt);
                    rs->seg_counts[q] = cnt;
                }
                pkg->ctx.seg_storage      = rs->seg_storage;
                pkg->ctx.seg_counts       = rs->seg_counts;
                pkg->ctx.view_query_count = rs->query_count;
            }
            else
            {
                pkg->ctx.seg_storage      = NULL;
                pkg->ctx.seg_counts       = NULL;
                pkg->ctx.view_query_count = 0;
            }
            pkg->execute           = rs->params.execute;
            pkg->user_data         = rs->params.user_data;
            pkg->dt                = dt;
            pkg->defer.cmds           = NULL;
            pkg->defer.count          = 0;
            pkg->defer.capacity       = 0;
            pkg->defer.arena          = NULL;
            pkg->defer.arena_used     = 0;
            pkg->defer.arena_capacity = 0;
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
            if (pkgs[t].defer.arena)
                ke_free(pkgs[t].defer.arena);
        }
    }
}

// Walk every render-phase system; mark each component it reads as
// double-buffered so the sim→render swap has a back buffer to fill. Tag
// components (size 0, e.g. render-resource cids) are skipped by the ecs impl.
static void runtime_infer_snapshots(runtime_handle *h, size_t first, size_t last)
{
    if (!h->state.ecs->set_double_buffered) return;
    for (size_t si = first; si < last; si++)
    {
        registered_system *rs = &h->state.systems[si];
        if (rs->params.phase != KE_PHASE_RENDER) continue;
        for (uint32_t a = 0; a < rs->params.access_count; a++)
            h->state.ecs->set_double_buffered(h->state.ecs, rs->params.access_list[a].cid);
    }
}

// Bind each system's copied query decls to real ECS queries. A render-phase
// system's terms are mapped through snapshot_cid first, so the segments its body
// reads via ke_system_ctx_view come from the snapshot side — matching what
// ke_system_ctx_get already does per-entity. snapshot_cid returns the cid
// unchanged for anything not double-buffered (tags, sim-only components), so a
// mixed query resolves correctly.
//
// Must run after runtime_infer_snapshots: the snapshot cids do not exist before it.
static void runtime_bind_queries(runtime_handle *h, size_t first, size_t last)
{
    if (!h->state.ecs->query_register) return;
    for (size_t si = first; si < last; si++)
    {
        registered_system *rs = &h->state.systems[si];
        const bool to_snapshot =
            rs->params.phase == KE_PHASE_RENDER && h->state.ecs->snapshot_cid != NULL;

        for (uint32_t q = 0; q < rs->query_count; q++)
        {
            const ke_query_decl *qd = &rs->query_decls[q];
            ke_component_id      cids[KE_QUERY_MAX_TERMS];
            for (uint32_t t = 0; t < qd->term_count; t++)
            {
                ke_component_id cid = qd->terms[t].cid;
                if (to_snapshot) cid = h->state.ecs->snapshot_cid(h->state.ecs, cid);
                cids[t] = cid;
            }
            rs->query_ids[q] = h->state.ecs->query_register(h->state.ecs, cids, qd->term_count);
        }
    }
}

// Snapshot inference + query binding for every system not yet prepared. Both run
// at the top of a tick rather than at registration: inference must observe every
// system's access list before any render query is bound to a snapshot cid.
static void runtime_prepare_systems(runtime_handle *h)
{
    if (h->state.systems_prepared >= h->state.system_count) return;
    const size_t first = h->state.systems_prepared;
    const size_t last  = h->state.system_count;
    runtime_infer_snapshots(h, first, last);
    runtime_bind_queries(h, first, last);
    h->state.systems_prepared = last;
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

    // Snapshot inference + query binding for any system registered since the last
    // tick. Ahead of every phase: a render system's queries must already resolve
    // to the snapshot side the first time its body runs.
    runtime_prepare_systems(h);

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

    // Sim→render boundary (§16): freeze the sim's just-written live side into the
    // snapshot the render phase reads.
    if (h->state.ecs->swap_snapshots)
    {
        if (!h->state.ecs->swap_snapshots(h->state.ecs, out_error))
            return false;
    }
    runtime_run_phase(h, KE_PHASE_RENDER, dt);

    return true;
}

static void runtime_destroy(ke_runtime *self)
{
    if (!self || !self->handle) return;
    runtime_handle *h = (runtime_handle *)self->handle;

    if (h->state.systems)
    {
        for (size_t i = 0; i < h->state.system_count; i++)
            if (h->state.systems[i].seg_storage) ke_free(h->state.systems[i].seg_storage);
        ke_free(h->state.systems);
    }
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
