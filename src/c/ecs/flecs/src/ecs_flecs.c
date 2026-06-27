#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/allocator/allocator.h>

#include <abort_guard.h>

#include <flecs.h>

#include <stdalign.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Storage-only flecs wrapper. Implements the ke_ecs vtable by delegating to
// flecs's archetype storage + query engine. The scheduler is OUR ke_runtime;
// flecs's pipeline/system/timer addons are not referenced.

// ── Abort interception ───────────────────────────────────────────────────────
//
// flecs calls ecs_os_api.abort_() on internal assertion failures.  We replace
// that slot with our own handler that delegates to ke_abort_guard_longjmp().
// If no guard is active we log to stderr and call _exit(134) — no OS dialog.
// ecs_os_api is global; we install once (guarded by s_os_api_installed).

const ke_error_type KE_ERROR_ECS_FLECS_FATAL = {
    "ke.ecs.flecs.fatal", NULL
};

const char *ke_ecs_flecs_get_last_fatal_message(void)
{
    return ke_abort_guard_last_message();
}

static void flecs_log_handler(int32_t level, const char *file, int32_t line, const char *msg)
{
    // flecs uses negative levels for fatal/error messages.
    if (level < 0 && msg)
        ke_abort_guard_set_message(file, (int)line, msg);
}

static void flecs_abort_handler(void)
{
    if (ke_abort_guard_longjmp()) return;  // longjmp fired — control transferred
    fprintf(stderr, "[ke_ecs_flecs FATAL] %s\n",
            ke_abort_guard_last_message() ? ke_abort_guard_last_message() : "(no message captured)");
    fflush(stderr);
    _exit(134);
}

static bool s_os_api_installed = false;

static void install_flecs_os_api(void)
{
    if (s_os_api_installed) return;
    // Populate defaults first so we only override the two slots we care about
    // and don't accidentally zero-out malloc/free/threading pointers.
    ecs_os_set_api_defaults();
    ecs_os_api_t api = ecs_os_get_api();
    api.log_   = flecs_log_handler;
    api.abort_ = flecs_abort_handler;
    ecs_os_set_api(&api);
    s_os_api_installed = true;
}

#define KE_FLECS_GUARD(context_label, fail_return) \
    KE_ABORT_GUARD(&KE_ERROR_ECS_FLECS_FATAL, context_label, fail_return)

#define KE_FLECS_GUARD_END() KE_ABORT_GUARD_END()

typedef struct query_cache_entry
{
    ke_component_id cid;
    ecs_query_t    *query;
    size_t          element_size;
} query_cache_entry;

// A double-buffered component (RuntimeArchitectureV2.md §16): `live` is the cid
// sim systems read/write; `snap` is the hidden back buffer render systems read.
// swap_snapshots copies live → snap at the sim→render phase boundary.
typedef struct snap_pair
{
    ke_component_id live;
    ke_component_id snap;
    size_t          element_size;
} snap_pair;

typedef struct ecs_flecs_state
{
    ecs_world_t  *world;
    bool          world_corrupted; // set when KE_FLECS_GUARD catches a fatal

    snap_pair *snaps;
    size_t     snap_count;
    size_t     snap_capacity;

    // Query cache — populated eagerly at component_register (so the parallel
    // wave never creates a query, which flecs forbids in readonly mode). During
    // a wave the cache is read-only, so concurrent lookups are safe.
    query_cache_entry *queries;
    size_t             query_count;
    size_t             query_capacity;
} ecs_flecs_state;

// Per-thread query scratch. A query packs its results into a contiguous buffer
// and returns a pointer to it; with parallel systems each worker needs its own,
// so the scratch is thread-local. The buffers are registered in a lock-free pool
// (atomic-bumped slot, no mutex) so destroy can free them all.
#define KE_FLECS_MAX_THREADS 64

typedef struct thread_scratch
{
    ke_entity *entities;
    size_t     entity_capacity;
    char      *data;
    size_t     data_capacity;
} thread_scratch;

static thread_scratch    g_scratch[KE_FLECS_MAX_THREADS];
static _Atomic unsigned  g_scratch_count = 0;
static _Thread_local int t_scratch_slot  = -1;

static thread_scratch *scratch_for_thread(void)
{
    if (t_scratch_slot < 0)
    {
        unsigned slot = atomic_fetch_add(&g_scratch_count, 1u);
        if (slot >= KE_FLECS_MAX_THREADS) return NULL;
        t_scratch_slot = (int)slot;
    }
    return &g_scratch[t_scratch_slot];
}

typedef struct ecs_flecs_handle
{
    ke_ecs          api;
    ecs_flecs_state state;
} ecs_flecs_handle;

// ── Helpers ─────────────────────────────────────────────────────────────────

static query_cache_entry *find_or_create_query(ecs_flecs_state *s, ke_component_id cid)
{
    for (size_t i = 0; i < s->query_count; i++)
    {
        if (s->queries[i].cid == cid) return &s->queries[i];
    }

    if (s->query_count == s->query_capacity)
    {
        size_t new_cap = s->query_capacity ? s->query_capacity * 2 : 8;
        query_cache_entry *new_buf = (query_cache_entry *)ke_alloc(sizeof(query_cache_entry) * new_cap, alignof(query_cache_entry));
        if (!new_buf) return NULL;
        if (s->queries)
        {
            memcpy(new_buf, s->queries, sizeof(query_cache_entry) * s->query_count);
            ke_free(s->queries);
        }
        s->queries = new_buf;
        s->query_capacity = new_cap;
    }

    ecs_query_desc_t desc = {0};
    desc.filter.terms[0].id = (ecs_id_t)cid;
    ecs_query_t *q = ecs_query_init(s->world, &desc);
    if (!q) return NULL;

    const ecs_type_info_t *ti = ecs_get_type_info(s->world, (ecs_id_t)cid);
    size_t elem_size = ti ? (size_t)ti->size : 0;

    query_cache_entry *entry = &s->queries[s->query_count++];
    entry->cid          = cid;
    entry->query        = q;
    entry->element_size = elem_size;
    return entry;
}

static bool grow_scratch_entities(thread_scratch *ts, size_t needed)
{
    if (needed <= ts->entity_capacity) return true;
    size_t new_cap = ts->entity_capacity ? ts->entity_capacity * 2 : 16;
    while (new_cap < needed) new_cap *= 2;
    ke_entity *new_buf = (ke_entity *)ke_alloc(sizeof(ke_entity) * new_cap, alignof(ke_entity));
    if (!new_buf) return false;
    if (ts->entities) ke_free(ts->entities);
    ts->entities        = new_buf;
    ts->entity_capacity = new_cap;
    return true;
}

static bool grow_scratch_data(thread_scratch *ts, size_t needed_bytes)
{
    if (needed_bytes <= ts->data_capacity) return true;
    size_t new_cap = ts->data_capacity ? ts->data_capacity * 2 : 256;
    while (new_cap < needed_bytes) new_cap *= 2;
    char *new_buf = (char *)ke_alloc(new_cap, alignof(max_align_t));
    if (!new_buf) return false;
    if (ts->data) ke_free(ts->data);
    ts->data          = new_buf;
    ts->data_capacity = new_cap;
    return true;
}

// ── Vtable impls ────────────────────────────────────────────────────────────

static ke_entity ecs_flecs_entity_create(ke_ecs *self)
{
    if (!self || !self->handle) return 0;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;
    KE_FLECS_GUARD("flecs fatal in entity_create", { h->state.world_corrupted = true; return 0; });
    ke_entity result = (ke_entity)ecs_new_w_id(h->state.world, 0);
    KE_FLECS_GUARD_END();
    return result;
}

static void ecs_flecs_entity_destroy(ke_ecs *self, ke_entity entity)
{
    if (!self || !self->handle || entity == 0) return;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;
    if (!ecs_is_alive(h->state.world, (ecs_entity_t)entity)) return;
    ecs_delete(h->state.world, (ecs_entity_t)entity);
}

static ke_component_id ecs_flecs_component_register(ke_ecs *self, const char *name, size_t size)
{
    if (!self || !self->handle || !name) return 0;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;
    KE_FLECS_GUARD("flecs fatal in component_register", { h->state.world_corrupted = true; return 0; });

    // Reuse if already registered with the same name (idempotent for module reloads).
    ecs_entity_t existing = ecs_lookup(h->state.world, name);
    if (existing != 0) { find_or_create_query(&h->state, (ke_component_id)existing); KE_FLECS_GUARD_END(); return (ke_component_id)existing; }

    ecs_entity_desc_t edesc = {0};
    edesc.name = name;
    ecs_entity_t e = ecs_entity_init(h->state.world, &edesc);

    // A zero-size component is a tag (entity id, no data). flecs asserts if asked
    // to init a component with size 0, so register it as a pure tag — valid in
    // add/has/query and as a dependency key (render-resource cids are tags).
    if (size == 0)
    {
        // Warm the query now: creating a query is forbidden once the world enters
        // readonly mode during a parallel wave, so all queries must exist upfront.
        find_or_create_query(&h->state, (ke_component_id)e);
        KE_FLECS_GUARD_END();
        return (ke_component_id)e;
    }

    ecs_component_desc_t cdesc = {0};
    cdesc.entity = e;
    cdesc.type.size      = (ecs_size_t)size;
    cdesc.type.alignment = (ecs_size_t)alignof(max_align_t);
    ke_component_id cid = (ke_component_id)ecs_component_init(h->state.world, &cdesc);

    find_or_create_query(&h->state, cid); // warm before any readonly wave (see above)
    KE_FLECS_GUARD_END();
    return cid;
}

static bool ecs_flecs_component_lookup(ke_ecs *self, const char *name, ke_component_meta *out_meta, ke_error **out_error)
{
    if (!self || !self->handle || !name)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        return false;
    }
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;

    ecs_entity_t e = ecs_lookup(h->state.world, name);
    if (e == 0)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_NOT_FOUND, "component not found");
        return false;
    }

    const ecs_type_info_t *ti = ecs_get_type_info(h->state.world, e);
    if (!ti)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_NOT_FOUND, "component type info not found");
        return false;
    }

    if (out_meta)
    {
        out_meta->cid         = (ke_component_id)e;
        out_meta->size        = (size_t)ti->size;
        out_meta->fields      = NULL;  // field reflection not used through this impl
        out_meta->field_count = 0;
    }
    return true;
}

static void *ecs_flecs_component_add(ke_ecs *self, ke_entity entity, ke_component_id component)
{
    if (!self || !self->handle || entity == 0 || component == 0) return NULL;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;
    if (!ecs_is_alive(h->state.world, (ecs_entity_t)entity)) return NULL;
    KE_FLECS_GUARD("flecs fatal in component_add", { h->state.world_corrupted = true; return NULL; });
    ecs_add_id(h->state.world, (ecs_entity_t)entity, (ecs_id_t)component);
    void *ptr = ecs_get_mut_id(h->state.world, (ecs_entity_t)entity, (ecs_id_t)component);
    KE_FLECS_GUARD_END();
    return ptr;
}

static void ecs_flecs_component_remove(ke_ecs *self, ke_entity entity, ke_component_id component)
{
    if (!self || !self->handle || entity == 0 || component == 0) return;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;
    if (!ecs_is_alive(h->state.world, (ecs_entity_t)entity)) return;
    ecs_remove_id(h->state.world, (ecs_entity_t)entity, (ecs_id_t)component);
}

static void *ecs_flecs_component_get(ke_ecs *self, ke_entity entity, ke_component_id component)
{
    if (!self || !self->handle || entity == 0 || component == 0) return NULL;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;
    // Guard against unregistered components or dead entities.
    if (!ecs_is_alive(h->state.world, (ecs_entity_t)entity)) return NULL;
    if (!ecs_has_id(h->state.world, (ecs_entity_t)entity, (ecs_id_t)component)) return NULL;
    // ecs_get_id (const) — NOT ecs_get_mut_id — so this is safe inside readonly
    // mode (parallel reads). The mut variant requires a stage and asserts in
    // readonly. The returned pointer is the live storage; the contract exposes it
    // as void* (sim writes through it directly — a plain memory write, not a
    // flecs op, so it is allowed and never adds the component structurally).
    return (void *)ecs_get_id(h->state.world, (ecs_entity_t)entity, (ecs_id_t)component);
}

static void ecs_flecs_query(ke_ecs *self, ke_component_id component,
                            ke_entity **out_entities, void **out_data, size_t *out_count)
{
    if (out_entities) *out_entities = NULL;
    if (out_data)     *out_data     = NULL;
    if (out_count)    *out_count    = 0;
    if (!self || !self->handle || component == 0) return;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;

    thread_scratch *ts = scratch_for_thread(); // per-thread → parallel-safe
    if (!ts) return;

    KE_FLECS_GUARD("flecs fatal in query", { h->state.world_corrupted = true; return; });
    query_cache_entry *entry = find_or_create_query(&h->state, component);
    if (!entry || !entry->query) return;

    // Walk the query archetypes and pack entities + component data into scratch.
    size_t total = 0;
    ecs_iter_t it = ecs_query_iter(h->state.world, entry->query);
    while (ecs_query_next(&it))
    {
        if (!grow_scratch_entities(ts, total + (size_t)it.count)) return;
        if (entry->element_size > 0 &&
            !grow_scratch_data(ts, (total + (size_t)it.count) * entry->element_size)) return;

        memcpy(ts->entities + total, it.entities, sizeof(ecs_entity_t) * (size_t)it.count);

        if (entry->element_size > 0)
        {
            // flecs query fields are 1-based; the term we added in find_or_create_query
            // sits at index 1.
            void *src = ecs_field_w_size(&it, entry->element_size, 1);
            if (src)
            {
                memcpy(ts->data + total * entry->element_size, src,
                       entry->element_size * (size_t)it.count);
            }
        }
        total += (size_t)it.count;
    }

    if (out_entities) *out_entities = ts->entities;
    if (out_data)     *out_data     = ts->data;
    if (out_count)    *out_count    = total;
    KE_FLECS_GUARD_END();
}

// ── Snapshot (double-buffer) support ─────────────────────────────────────────

static snap_pair *find_snap_pair(ecs_flecs_state *s, ke_component_id live)
{
    for (size_t i = 0; i < s->snap_count; i++)
        if (s->snaps[i].live == live) return &s->snaps[i];
    return NULL;
}

static void ecs_flecs_set_double_buffered(ke_ecs *self, ke_component_id cid)
{
    if (!self || !self->handle || cid == 0) return;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;
    if (find_snap_pair(&h->state, cid)) return; // already double-buffered

    const ecs_type_info_t *ti = ecs_get_type_info(h->state.world, (ecs_id_t)cid);
    size_t size = ti ? (size_t)ti->size : 0;
    if (size == 0) return; // tag components (e.g. render-resource cids) are not buffered

    KE_FLECS_GUARD("flecs fatal in set_double_buffered", { h->state.world_corrupted = true; return; });
    ecs_entity_t snap_e = (ecs_entity_t)ecs_new_w_id(h->state.world, 0);
    ecs_component_desc_t cdesc = {0};
    cdesc.entity         = snap_e;
    cdesc.type.size      = (ecs_size_t)size;
    cdesc.type.alignment = (ecs_size_t)alignof(max_align_t);
    ke_component_id snap_cid = (ke_component_id)ecs_component_init(h->state.world, &cdesc);
    // Warm the snapshot's query now — render systems read the snapshot cid inside
    // the readonly parallel wave, where creating a query is forbidden.
    find_or_create_query(&h->state, snap_cid);
    KE_FLECS_GUARD_END();

    if (h->state.snap_count == h->state.snap_capacity)
    {
        size_t new_cap = h->state.snap_capacity ? h->state.snap_capacity * 2 : 8;
        snap_pair *new_buf = (snap_pair *)ke_alloc(sizeof(snap_pair) * new_cap, alignof(snap_pair));
        if (!new_buf) return;
        if (h->state.snaps)
        {
            memcpy(new_buf, h->state.snaps, sizeof(snap_pair) * h->state.snap_count);
            ke_free(h->state.snaps);
        }
        h->state.snaps         = new_buf;
        h->state.snap_capacity = new_cap;
    }
    snap_pair *p     = &h->state.snaps[h->state.snap_count++];
    p->live          = cid;
    p->snap          = snap_cid;
    p->element_size  = size;
}

static ke_component_id ecs_flecs_component_register_v3(ke_ecs *self, const char *name,
                                                       size_t size, ke_component_flags flags)
{
    ke_component_id cid = ecs_flecs_component_register(self, name, size);
    if (cid != 0 && (flags & KE_COMPONENT_DOUBLE_BUFFERED))
        ecs_flecs_set_double_buffered(self, cid);
    return cid;
}

static ke_component_id ecs_flecs_snapshot_cid(ke_ecs *self, ke_component_id cid)
{
    if (!self || !self->handle) return cid;
    snap_pair *p = find_snap_pair(&((ecs_flecs_handle *)self->handle)->state, cid);
    return p ? p->snap : cid;
}

static void ecs_flecs_swap_snapshots(ke_ecs *self)
{
    if (!self || !self->handle) return;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;
    KE_FLECS_GUARD("flecs fatal in swap_snapshots", { h->state.world_corrupted = true; return; });
    thread_scratch *ts = scratch_for_thread(); // serial caller (phase boundary)
    if (!ts) return;

    for (size_t i = 0; i < h->state.snap_count; i++)
    {
        snap_pair *p = &h->state.snaps[i];

        // Pass 1: collect entities carrying the live component (no world mutation).
        query_cache_entry *entry = find_or_create_query(&h->state, p->live);
        if (!entry || !entry->query) continue;
        size_t total = 0;
        ecs_iter_t it = ecs_query_iter(h->state.world, entry->query);
        while (ecs_query_next(&it))
        {
            if (!grow_scratch_entities(ts, total + (size_t)it.count)) { total = 0; break; }
            memcpy(ts->entities + total, it.entities, sizeof(ecs_entity_t) * (size_t)it.count);
            total += (size_t)it.count;
        }

        // Pass 2: copy live → snap per entity (adds snap on first swap; safe
        // outside iteration even though it moves archetypes).
        for (size_t e = 0; e < total; e++)
        {
            ecs_entity_t ent = (ecs_entity_t)ts->entities[e];
            void *live = ecs_get_mut_id(h->state.world, ent, (ecs_id_t)p->live);
            void *snap = ecs_get_mut_id(h->state.world, ent, (ecs_id_t)p->snap);
            if (live && snap) memcpy(snap, live, p->element_size);
        }
    }
    KE_FLECS_GUARD_END();
}

static void ecs_flecs_concurrent_reads(ke_ecs *self, void (*body)(void *ctx), void *ctx)
{
    if (!body) return;
    if (!self || !self->handle) { body(ctx); return; }
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;
    if (h->state.world_corrupted) { body(ctx); return; }

    // Readonly mode lets the world be read from multiple threads (queries + gets)
    // with no internal mutation. Structural changes are forbidden here — the
    // runtime defers writes and applies them serially after this returns.
    KE_FLECS_GUARD("flecs fatal in concurrent_reads", { h->state.world_corrupted = true; return; });
    ecs_readonly_begin(h->state.world);
    body(ctx);
    ecs_readonly_end(h->state.world);
    KE_FLECS_GUARD_END();
}

static void ecs_flecs_destroy(ke_ecs *self)
{
    if (!self || !self->handle) return;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;

    if (!h->state.world_corrupted)
    {
        // Normal path: free queries, then tear down the flecs world.
        if (h->state.queries)
        {
            for (size_t i = 0; i < h->state.query_count; i++)
            {
                if (h->state.queries[i].query) ecs_query_fini(h->state.queries[i].query);
            }
        }
        if (h->state.world) ecs_fini(h->state.world);
    }
    // Always free our own allocations regardless of world state.
    if (h->state.queries) ke_free(h->state.queries);
    if (h->state.snaps)   ke_free(h->state.snaps);

    // Free the per-thread scratch pool (one ECS per process; all worker threads
    // have stopped querying by the time the ECS is destroyed).
    unsigned scratch_n = atomic_load(&g_scratch_count);
    if (scratch_n > KE_FLECS_MAX_THREADS) scratch_n = KE_FLECS_MAX_THREADS;
    for (unsigned i = 0; i < scratch_n; i++)
    {
        if (g_scratch[i].entities) { ke_free(g_scratch[i].entities); g_scratch[i].entities = NULL; g_scratch[i].entity_capacity = 0; }
        if (g_scratch[i].data)     { ke_free(g_scratch[i].data);     g_scratch[i].data = NULL;     g_scratch[i].data_capacity = 0; }
    }

    ke_free(h);
}

// ── Factory ─────────────────────────────────────────────────────────────────

ke_ecs_handle ke_ecs_flecs_create(const ke_ecs_flecs_params *params,
                                   ke_error                 **out_error)
{
    (void)params;

    install_flecs_os_api();

    ecs_flecs_handle *h = (ecs_flecs_handle *)ke_alloc(sizeof(ecs_flecs_handle), alignof(ecs_flecs_handle));
    if (!h)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "state allocation failed");
        return (ke_ecs_handle){0};
    }
    memset(h, 0, sizeof(*h));

    h->state.world = ecs_init();
    if (!h->state.world)
    {
        ke_free(h);
        KE_ERROR_SET(out_error, &KE_ERROR_NOT_INITIALIZED, "flecs world init failed");
        return (ke_ecs_handle){0};
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
    h->api.component_register_v3 = ecs_flecs_component_register_v3;
    h->api.set_double_buffered   = ecs_flecs_set_double_buffered;
    h->api.snapshot_cid          = ecs_flecs_snapshot_cid;
    h->api.swap_snapshots        = ecs_flecs_swap_snapshots;
    h->api.concurrent_reads      = ecs_flecs_concurrent_reads;

    return (ke_ecs_handle){ .ref = &h->api, .destroy = ecs_flecs_destroy };
}
