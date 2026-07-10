#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/allocator/allocator.h>

#include <abort_guard.h>

#include <flecs.h>

#include <stdalign.h>
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

typedef struct ecs_flecs_state
{
    ecs_world_t  *world;
    bool          world_corrupted; // set when KE_FLECS_GUARD catches a fatal

    // Query cache — populated eagerly at component_register (so no query is
    // ever created mid-tick, only at startup registration, single-threaded).
    query_cache_entry *queries;
    size_t             query_count;
    size_t             query_capacity;

    // Multi-term registered queries (the parallel-safe path; see registered_query).
    registered_query *rqueries;
    size_t            rquery_count;
    size_t            rquery_capacity;
} ecs_flecs_state;

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

static size_t ecs_flecs_component_size(ke_ecs *self, ke_component_id cid)
{
    if (!self || !self->handle || cid == 0) return 0;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;
    const ecs_type_info_t *ti = ecs_get_type_info(h->state.world, (ecs_id_t)cid);
    return ti ? (size_t)ti->size : 0;
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
    h->api.component_size     = ecs_flecs_component_size;
    h->api.query_register     = ecs_flecs_query_register;
    h->api.query_resolve      = ecs_flecs_query_resolve;

    return (ke_ecs_handle){ .ref = &h->api, .destroy = ecs_flecs_destroy };
}
