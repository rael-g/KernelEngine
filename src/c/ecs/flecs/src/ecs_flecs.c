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
} query_cache_entry;

// A multi-term query registered via query_register — the parallel-safe read path.
// query_resolve walks it single-threaded into ke_ecs_segment lists; the wave
// bodies then read those segments as plain memory (no flecs call).
typedef struct registered_query
{
    ecs_query_t *query;
    size_t       elem_sizes[KE_QUERY_MAX_TERMS]; // 0 for a tag term (no column)
    size_t       term_count;
} registered_query;

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

    // Every _snap component lives on a dedicated "shadow" entity, one per live
    // entity that owns at least one double-buffered component — NOT on the live
    // entity itself. A live entity's archetype can churn every frame (sim adds/
    // removes unrelated components via defer_flush); if _snap shared that
    // archetype, an unrelated structural change would relocate the snapshot
    // column too, invalidating any pointer a render read had already resolved —
    // fatal once render overlaps a future sim tick asynchronously (RuntimeArchitectureV2.md
    // §16 pipelining). The shadow entity's own archetype is touched only by
    // swap_snapshots (serial, at the phase boundary), never by a running wave.
    // shadow_link_cid (lazily registered) holds the live entity's shadow id.
    ke_component_id shadow_link_cid;

    // Query cache — populated eagerly at component_register (so the parallel
    // wave never creates a query, which flecs forbids in readonly mode). During
    // a wave the cache is read-only, so concurrent lookups are safe.
    query_cache_entry *queries;
    size_t             query_count;
    size_t             query_capacity;

    // Multi-term registered queries (the parallel-safe path; see registered_query).
    registered_query *rqueries;
    size_t            rquery_count;
    size_t            rquery_capacity;
} ecs_flecs_state;

// Per-thread entity scratch, used by the serial paths that collect entity ids
// before mutating them (swap_snapshots). Thread-local so the pool can also
// serve any future per-worker collection without a mutex; slots are handed out
// by an atomic bump so destroy can free them all.
#define KE_FLECS_MAX_THREADS 64

typedef struct thread_scratch
{
    ke_entity *entities;
    size_t     entity_capacity;
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

    query_cache_entry *entry = &s->queries[s->query_count++];
    entry->cid   = cid;
    entry->query = q;
    return entry;
}

// Lazily registers the hidden link component that maps a live entity to its
// shadow entity (see ecs_flecs_state's shadow_link_cid comment). Not a tag —
// it carries the shadow's ecs_entity_t — so it is a real, small component.
static ke_component_id shadow_link_cid(ecs_flecs_state *s)
{
    if (s->shadow_link_cid != 0) return s->shadow_link_cid;
    ecs_entity_desc_t edesc = {0};
    edesc.name = "ke.snapshot_shadow_link";
    ecs_entity_t e = ecs_entity_init(s->world, &edesc);
    ecs_component_desc_t cdesc = {0};
    cdesc.entity         = e;
    cdesc.type.size      = sizeof(ecs_entity_t);
    cdesc.type.alignment = (ecs_size_t)alignof(ecs_entity_t);
    s->shadow_link_cid = (ke_component_id)ecs_component_init(s->world, &cdesc);
    return s->shadow_link_cid;
}

// Returns `live`'s shadow entity, creating it (and the link) on first use. Only
// called from swap_snapshots — serial, at the phase boundary — so adding the
// link component to `live` here (which moves its archetype once) never races
// a running wave.
static ecs_entity_t get_or_create_shadow(ecs_flecs_state *s, ecs_entity_t live)
{
    ke_component_id link = shadow_link_cid(s);
    if (link == 0) return 0;
    const ecs_entity_t *existing =
        (const ecs_entity_t *)ecs_get_id(s->world, live, (ecs_id_t)link);
    if (existing) return *existing;

    ecs_entity_t shadow = ecs_new_w_id(s->world, 0);
    ecs_entity_t *slot  = (ecs_entity_t *)ecs_get_mut_id(s->world, live, (ecs_id_t)link);
    if (slot) *slot = shadow;
    return shadow;
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

static ke_entity ecs_flecs_entity_reserve(ke_ecs *self)
{
    if (!self || !self->handle) return 0;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;
    if (h->state.world_corrupted) return 0;
    // ecs_new_id is the atomic id allocator: safe to call while the world is in
    // readonly mode (a parallel wave) from any thread. It returns an empty, alive
    // entity — component storage is added later through the defer queue.
    KE_FLECS_GUARD("flecs fatal in entity_reserve", { h->state.world_corrupted = true; return 0; });
    ke_entity result = (ke_entity)ecs_new_id(h->state.world);
    KE_FLECS_GUARD_END();
    return result;
}

static void ecs_flecs_entity_destroy(ke_ecs *self, ke_entity entity)
{
    if (!self || !self->handle || entity == 0) return;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;
    if (!ecs_is_alive(h->state.world, (ecs_entity_t)entity)) return;

    // Cascade to the snapshot shadow (see ecs_flecs_state's shadow_link_cid
    // comment) — otherwise every entity that ever carried a double-buffered
    // component leaks its shadow for the life of the process.
    if (h->state.shadow_link_cid != 0)
    {
        const ecs_entity_t *shadow = (const ecs_entity_t *)
            ecs_get_id(h->state.world, (ecs_entity_t)entity, (ecs_id_t)h->state.shadow_link_cid);
        if (shadow && ecs_is_alive(h->state.world, *shadow))
            ecs_delete(h->state.world, *shadow);
    }
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
    // A tag carries no data. Asking for its storage pointer asserts inside the
    // backend, so only sized components resolve to one; a tag yields NULL.
    const ecs_type_info_t *ti = ecs_get_type_info(h->state.world, (ecs_id_t)component);
    void *ptr = (ti && ti->size > 0)
                    ? ecs_get_mut_id(h->state.world, (ecs_entity_t)entity, (ecs_id_t)component)
                    : NULL;
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

// ── Resolved multi-term queries (parallel-safe read path) ────────────────────

static ke_query_id ecs_flecs_query_register(ke_ecs *self, const ke_component_id *cids, size_t cid_count)
{
    if (!self || !self->handle || !cids || cid_count == 0 || cid_count > KE_QUERY_MAX_TERMS)
        return KE_QUERY_INVALID;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;
    if (h->state.world_corrupted) return KE_QUERY_INVALID;

    KE_FLECS_GUARD("flecs fatal in query_register", {
        h->state.world_corrupted = true; return KE_QUERY_INVALID;
    });

    ecs_query_desc_t desc = {0};
    for (size_t i = 0; i < cid_count; i++)
        desc.filter.terms[i].id = (ecs_id_t)cids[i];
    ecs_query_t *q = ecs_query_init(h->state.world, &desc);
    if (!q) { KE_FLECS_GUARD_END(); return KE_QUERY_INVALID; }

    if (h->state.rquery_count == h->state.rquery_capacity)
    {
        size_t new_cap = h->state.rquery_capacity ? h->state.rquery_capacity * 2 : 8;
        registered_query *nb = (registered_query *)ke_alloc(sizeof(registered_query) * new_cap, alignof(registered_query));
        if (!nb) { ecs_query_fini(q); KE_FLECS_GUARD_END(); return KE_QUERY_INVALID; }
        if (h->state.rqueries)
        {
            memcpy(nb, h->state.rqueries, sizeof(registered_query) * h->state.rquery_count);
            ke_free(h->state.rqueries);
        }
        h->state.rqueries        = nb;
        h->state.rquery_capacity = new_cap;
    }

    registered_query *rq = &h->state.rqueries[h->state.rquery_count];
    rq->query      = q;
    rq->term_count = cid_count;
    for (size_t i = 0; i < cid_count; i++)
    {
        const ecs_type_info_t *ti = ecs_get_type_info(h->state.world, (ecs_id_t)cids[i]);
        rq->elem_sizes[i] = ti ? (size_t)ti->size : 0;
    }
    ke_query_id id = (ke_query_id)(h->state.rquery_count + 1);
    h->state.rquery_count++;
    KE_FLECS_GUARD_END();
    return id;
}

static void ecs_flecs_query_resolve(ke_ecs *self, ke_query_id query,
                                    ke_ecs_segment *out_segments, size_t max_segments, size_t *out_count)
{
    if (out_count) *out_count = 0;
    if (!self || !self->handle || query == KE_QUERY_INVALID || !out_segments || max_segments == 0) return;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;
    if (h->state.world_corrupted) return;
    size_t idx = (size_t)query - 1;
    if (idx >= h->state.rquery_count) return;
    registered_query *rq = &h->state.rqueries[idx];
    if (!rq->query) return;

    KE_FLECS_GUARD("flecs fatal in query_resolve", { h->state.world_corrupted = true; return; });

    size_t seg = 0;
    ecs_iter_t it = ecs_query_iter(h->state.world, rq->query);
    while (ecs_query_next(&it))
    {
        if (seg >= max_segments) { ecs_iter_fini(&it); break; }
        ke_ecs_segment *s = &out_segments[seg];
        s->entities = (const ke_entity *)it.entities;
        s->count    = (size_t)it.count;
        for (size_t t = 0; t < rq->term_count; t++)
            s->columns[t] = rq->elem_sizes[t] ? ecs_field_w_size(&it, rq->elem_sizes[t], (int32_t)(t + 1)) : NULL;
        for (size_t t = rq->term_count; t < KE_QUERY_MAX_TERMS; t++)
            s->columns[t] = NULL;
        seg++;
    }
    if (out_count) *out_count = seg;
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

    KE_FLECS_GUARD("flecs fatal in set_double_buffered", {
        h->state.world_corrupted = true; return;
    });
    ecs_entity_t snap_e = (ecs_entity_t)ecs_new_w_id(h->state.world, 0);
    ecs_component_desc_t cdesc = {0};
    cdesc.entity         = snap_e;
    cdesc.type.size      = (ecs_size_t)size;
    cdesc.type.alignment = (ecs_size_t)alignof(max_align_t);
    ke_component_id snap_cid = (ke_component_id)ecs_component_init(h->state.world, &cdesc);
    if (snap_cid == 0) { KE_FLECS_GUARD_END(); return; } // ecs_component_init failed
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

// Read-only lookup (ecs_get_id, not ecs_get_mut_id) — safe inside a readonly
// parallel wave, same category as component_get. Never creates the shadow
// (that only happens from swap_snapshots, serially): if none exists yet
// (asked before the first swap involving this entity), the entity is
// returned unchanged and the paired component_get(live, snap_cid) call
// simply finds nothing, exactly like a never-swapped component does today.
static ke_entity ecs_flecs_snapshot_entity(ke_ecs *self, ke_entity live)
{
    if (!self || !self->handle || live == 0) return live;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;
    if (h->state.shadow_link_cid == 0) return live;
    const ecs_entity_t *shadow = (const ecs_entity_t *)
        ecs_get_id(h->state.world, (ecs_entity_t)live, (ecs_id_t)h->state.shadow_link_cid);
    return shadow ? (ke_entity)*shadow : live;
}

static bool ecs_flecs_swap_snapshots(ke_ecs *self, ke_error **out_error)
{
    if (!self || !self->handle) return true;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;
    KE_FLECS_GUARD("flecs fatal in swap_snapshots", {
        h->state.world_corrupted = true;
        KE_ERROR_SET(out_error, &KE_ERROR_ECS_FLECS_FATAL,
                     ke_abort_guard_last_message() ? ke_abort_guard_last_message()
                                                   : "flecs fatal in swap_snapshots");
        return false;
    });
    thread_scratch *ts = scratch_for_thread(); // serial caller (phase boundary)
    if (!ts) { KE_FLECS_GUARD_END(); return true; }

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
            if (!grow_scratch_entities(ts, total + (size_t)it.count)) { total = 0; ecs_iter_fini(&it); break; }
            memcpy(ts->entities + total, it.entities, sizeof(ecs_entity_t) * (size_t)it.count);
            total += (size_t)it.count;
        }

        // Pass 2: copy live → each entity's shadow's snap component. Creating the
        // shadow (first swap for that entity) and adding the snap component to it
        // (first swap for that pair) are both safe here, outside iteration, even
        // though either can move an archetype — the shadow's, never the live
        // entity's, so a render read already resolved against a snap column is
        // never invalidated by unrelated churn on the live side (see
        // ecs_flecs_state's shadow_link_cid comment).
        if (p->snap == 0) continue; // snap creation failed; skip to avoid ecs abort
        for (size_t e = 0; e < total; e++)
        {
            ecs_entity_t ent = (ecs_entity_t)ts->entities[e];
            if (!ecs_is_alive(h->state.world, ent)) continue;
            ecs_entity_t shadow = get_or_create_shadow(&h->state, ent);
            if (shadow == 0) continue;
            void *live = ecs_get_mut_id(h->state.world, ent, (ecs_id_t)p->live);
            void *snap = ecs_get_mut_id(h->state.world, shadow, (ecs_id_t)p->snap);
            if (live && snap) memcpy(snap, live, p->element_size);
        }
    }
    KE_FLECS_GUARD_END();
    return true;
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
        for (size_t i = 0; i < h->state.rquery_count; i++)
        {
            if (h->state.rqueries[i].query) ecs_query_fini(h->state.rqueries[i].query);
        }
        if (h->state.world) ecs_fini(h->state.world);
    }
    // Always free our own allocations regardless of world state.
    if (h->state.queries)  ke_free(h->state.queries);
    if (h->state.rqueries) ke_free(h->state.rqueries);
    if (h->state.snaps)    ke_free(h->state.snaps);

    // Free the per-thread scratch pool (one ECS per process; all worker threads
    // have stopped querying by the time the ECS is destroyed).
    unsigned scratch_n = atomic_load(&g_scratch_count);
    if (scratch_n > KE_FLECS_MAX_THREADS) scratch_n = KE_FLECS_MAX_THREADS;
    for (unsigned i = 0; i < scratch_n; i++)
    {
        if (g_scratch[i].entities) { ke_free(g_scratch[i].entities); g_scratch[i].entities = NULL; g_scratch[i].entity_capacity = 0; }
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
    h->api.entity_reserve     = ecs_flecs_entity_reserve;
    h->api.entity_destroy     = ecs_flecs_entity_destroy;
    h->api.component_register = ecs_flecs_component_register;
    h->api.component_lookup   = ecs_flecs_component_lookup;
    h->api.component_add      = ecs_flecs_component_add;
    h->api.component_remove   = ecs_flecs_component_remove;
    h->api.component_get      = ecs_flecs_component_get;
    h->api.component_register_v3 = ecs_flecs_component_register_v3;
    h->api.set_double_buffered   = ecs_flecs_set_double_buffered;
    h->api.snapshot_cid          = ecs_flecs_snapshot_cid;
    h->api.swap_snapshots        = ecs_flecs_swap_snapshots;
    h->api.concurrent_reads      = ecs_flecs_concurrent_reads;
    h->api.query_register        = ecs_flecs_query_register;
    h->api.query_resolve         = ecs_flecs_query_resolve;
    h->api.snapshot_entity       = ecs_flecs_snapshot_entity;

    return (ke_ecs_handle){ .ref = &h->api, .destroy = ecs_flecs_destroy };
}
