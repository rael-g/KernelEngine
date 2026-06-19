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
    size_t          element_size;
} query_cache_entry;

typedef struct ecs_flecs_state
{
    ecs_world_t  *world;
    bool          world_corrupted; // set when KE_FLECS_GUARD catches a fatal

    // Query cache — first call per cid creates the flecs query and we keep it.
    query_cache_entry *queries;
    size_t             query_count;
    size_t             query_capacity;

    // Scratch buffers for query results: entities flat array + component data
    // packed contiguously. Reused on every query call.
    ke_entity *scratch_entities;
    size_t     scratch_entity_capacity;
    char      *scratch_data;
    size_t     scratch_data_capacity;
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

    const ecs_type_info_t *ti = ecs_get_type_info(s->world, (ecs_id_t)cid);
    size_t elem_size = ti ? (size_t)ti->size : 0;

    query_cache_entry *entry = &s->queries[s->query_count++];
    entry->cid          = cid;
    entry->query        = q;
    entry->element_size = elem_size;
    return entry;
}

static bool grow_scratch_entities(ecs_flecs_state *s, size_t needed)
{
    if (needed <= s->scratch_entity_capacity) return true;
    size_t new_cap = s->scratch_entity_capacity ? s->scratch_entity_capacity * 2 : 16;
    while (new_cap < needed) new_cap *= 2;
    ke_entity *new_buf = (ke_entity *)ke_alloc(sizeof(ke_entity) * new_cap, alignof(ke_entity));
    if (!new_buf) return false;
    if (s->scratch_entities) ke_free(s->scratch_entities);
    s->scratch_entities         = new_buf;
    s->scratch_entity_capacity  = new_cap;
    return true;
}

static bool grow_scratch_data(ecs_flecs_state *s, size_t needed_bytes)
{
    if (needed_bytes <= s->scratch_data_capacity) return true;
    size_t new_cap = s->scratch_data_capacity ? s->scratch_data_capacity * 2 : 256;
    while (new_cap < needed_bytes) new_cap *= 2;
    char *new_buf = (char *)ke_alloc(new_cap, alignof(max_align_t));
    if (!new_buf) return false;
    if (s->scratch_data) ke_free(s->scratch_data);
    s->scratch_data          = new_buf;
    s->scratch_data_capacity = new_cap;
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
    if (existing != 0) { KE_FLECS_GUARD_END(); return (ke_component_id)existing; }

    ecs_entity_desc_t edesc = {0};
    edesc.name = name;
    ecs_entity_t e = ecs_entity_init(h->state.world, &edesc);

    ecs_component_desc_t cdesc = {0};
    cdesc.entity = e;
    cdesc.type.size      = (ecs_size_t)size;
    cdesc.type.alignment = (ecs_size_t)alignof(max_align_t);
    ke_component_id cid = (ke_component_id)ecs_component_init(h->state.world, &cdesc);

    KE_FLECS_GUARD_END();
    return cid;
}

static ke_result ecs_flecs_component_lookup(ke_ecs *self, const char *name, ke_component_meta *out_meta, ke_error **out_error)
{
    if (!self || !self->handle || !name) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;

    ecs_entity_t e = ecs_lookup(h->state.world, name);
    if (e == 0) return KE_ERROR_SET(out_error, &KE_ERROR_NOT_FOUND, "component not found");

    const ecs_type_info_t *ti = ecs_get_type_info(h->state.world, e);
    if (!ti) return KE_ERROR_SET(out_error, &KE_ERROR_NOT_FOUND, "component type info not found");

    if (out_meta)
    {
        out_meta->cid         = (ke_component_id)e;
        out_meta->size        = (size_t)ti->size;
        out_meta->fields      = NULL;  // field reflection not used through this impl
        out_meta->field_count = 0;
    }
    return KE_OK;
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
    // Guard against unregistered components or dead entities — ecs_get_mut_id
    // asserts in both cases; ke_ecs contract says "returns NULL if not found."
    if (!ecs_is_alive(h->state.world, (ecs_entity_t)entity)) return NULL;
    if (!ecs_has_id(h->state.world, (ecs_entity_t)entity, (ecs_id_t)component)) return NULL;
    return ecs_get_mut_id(h->state.world, (ecs_entity_t)entity, (ecs_id_t)component);
}

static void ecs_flecs_query(ke_ecs *self, ke_component_id component,
                            ke_entity **out_entities, void **out_data, size_t *out_count)
{
    if (out_entities) *out_entities = NULL;
    if (out_data)     *out_data     = NULL;
    if (out_count)    *out_count    = 0;
    if (!self || !self->handle || component == 0) return;
    ecs_flecs_handle *h = (ecs_flecs_handle *)self->handle;

    KE_FLECS_GUARD("flecs fatal in query", { h->state.world_corrupted = true; return; });
    query_cache_entry *entry = find_or_create_query(&h->state, component);
    if (!entry || !entry->query) return;

    // Walk the query archetypes and pack entities + component data into scratch.
    size_t total = 0;
    ecs_iter_t it = ecs_query_iter(h->state.world, entry->query);
    while (ecs_query_next(&it))
    {
        if (!grow_scratch_entities(&h->state, total + (size_t)it.count)) return;
        if (entry->element_size > 0 &&
            !grow_scratch_data(&h->state, (total + (size_t)it.count) * entry->element_size)) return;

        memcpy(h->state.scratch_entities + total, it.entities, sizeof(ecs_entity_t) * (size_t)it.count);

        if (entry->element_size > 0)
        {
            // flecs query fields are 1-based; the term we added in find_or_create_query
            // sits at index 1.
            void *src = ecs_field_w_size(&it, entry->element_size, 1);
            if (src)
            {
                memcpy(h->state.scratch_data + total * entry->element_size, src,
                       entry->element_size * (size_t)it.count);
            }
        }
        total += (size_t)it.count;
    }

    if (out_entities) *out_entities = h->state.scratch_entities;
    if (out_data)     *out_data     = h->state.scratch_data;
    if (out_count)    *out_count    = total;
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
    if (h->state.queries)        ke_free(h->state.queries);
    if (h->state.scratch_entities) ke_free(h->state.scratch_entities);
    if (h->state.scratch_data)     ke_free(h->state.scratch_data);

    ke_free(h);
}

// ── Factory ─────────────────────────────────────────────────────────────────

ke_result ke_ecs_flecs_create(const ke_ecs_flecs_params *params,
                              ke_ecs_handle             *out_ecs,
                              ke_error                 **out_error)
{
    (void)params;
    if (!out_ecs) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");

    install_flecs_os_api();

    ecs_flecs_handle *h = (ecs_flecs_handle *)ke_alloc(sizeof(ecs_flecs_handle), alignof(ecs_flecs_handle));
    if (!h) return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "state allocation failed");
    memset(h, 0, sizeof(*h));

    h->state.world = ecs_init();
    if (!h->state.world)
    {
        ke_free(h);
        return KE_ERROR_SET(out_error, &KE_ERROR_NOT_INITIALIZED, "flecs world init failed");
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

    out_ecs->ref     = &h->api;
    out_ecs->destroy = ecs_flecs_destroy;
    return KE_OK;
}
