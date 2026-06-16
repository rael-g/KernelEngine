// ke_resource_cache impl — kernel built-in. Open-addressed table with
// tombstones for both the handle→entry and path→handle directions.
//
// destroy_fn is per-cache (set at construction). All resources in this cache
// share the same destructor (because per-domain caches are owned by the
// subsystem that knows how to free them).

#include <kernel_engine/resource_cache/resource_cache.h>
#include <kernel_engine/allocator/allocator.h>

#include <stdalign.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

static uint64_t ke_hash_string(const char *s)
{
    if (!s) return 0;
    uint64_t h = 5381;
    int c;
    while ((c = (unsigned char)*s++)) h = h * 33 ^ (uint64_t)c;
    return h;
}

// ── Internal state ──────────────────────────────────────────────────────────
//
// Two parallel tables:
//   (a) `resources` — open-addressed table of registered resources, keyed by
//       handle. Holds the refcount. Tombstones tracked so `release` can
//       reclaim slots without breaking probe chains.
//   (b) `paths` — same shape, keyed by FNV hash of the path string. Maps
//       path → handle for dedup lookups. Path entries don't hold a refcount;
//       the resource entry in (a) does.

typedef struct slot {
    uint64_t key;       // 0 = empty, UINT64_MAX = tombstone
    uint32_t refcount;  // resource entries only
    uint32_t handle;    // resource entries: redundant; path entries: target handle
} slot;

#define RC_EMPTY     0ULL
#define RC_TOMBSTONE UINT64_MAX

typedef struct table {
    slot         *slots;
    size_t        capacity;  // power of two
    size_t        occupied;  // active + tombstones
    size_t        active;    // active only
    ke_allocator *allocator;
} table;

typedef struct rc_state {
    ke_resource_cache         api;
    ke_allocator             *allocator;
    ke_resource_destroy_func  destroy_fn;
    void                     *destroy_ctx;
    table                     resources;
    table                     paths;
} rc_state;

// ── Table ops ───────────────────────────────────────────────────────────────

static ke_result table_init(table *t, ke_allocator *alloc, size_t initial_capacity) {
    t->allocator = alloc;
    t->capacity  = initial_capacity;
    t->occupied  = 0;
    t->active    = 0;
    t->slots = (slot *)alloc->alloc(alloc, initial_capacity * sizeof(slot), alignof(slot));
    if (!t->slots) return KE_ERROR_OUT_OF_MEMORY;
    memset(t->slots, 0, initial_capacity * sizeof(slot));
    return KE_OK;
}

static void table_destroy(table *t) {
    if (t->slots && t->allocator) t->allocator->free(t->allocator, t->slots);
    t->slots = NULL;
    t->capacity = t->occupied = t->active = 0;
}

// Finds the slot for `key`. Returns the matching active entry, or the first
// usable slot (preferring tombstones over empty so reinsertion keeps probe
// chains short). `*out_found` discriminates.
static size_t table_probe(const table *t, uint64_t key, bool *out_found) {
    size_t mask  = t->capacity - 1;
    size_t index = (size_t)(key & mask);
    size_t first_tombstone = SIZE_MAX;
    for (size_t i = 0; i < t->capacity; i++) {
        const slot *s = &t->slots[index];
        if (s->key == RC_EMPTY) {
            *out_found = false;
            return (first_tombstone != SIZE_MAX) ? first_tombstone : index;
        }
        if (s->key == RC_TOMBSTONE) {
            if (first_tombstone == SIZE_MAX) first_tombstone = index;
        } else if (s->key == key) {
            *out_found = true;
            return index;
        }
        index = (index + 1) & mask;
    }
    *out_found = false;
    return (first_tombstone != SIZE_MAX) ? first_tombstone : 0;
}

static ke_result table_rehash(table *t, size_t new_capacity);

static ke_result table_reserve(table *t) {
    if ((t->occupied + 1) * 10 < t->capacity * 7) return KE_OK;
    return table_rehash(t, t->capacity * 2);
}

static ke_result table_rehash(table *t, size_t new_capacity) {
    slot *old_slots = t->slots;
    size_t old_cap  = t->capacity;
    slot *new_slots = (slot *)t->allocator->alloc(t->allocator, new_capacity * sizeof(slot), alignof(slot));
    if (!new_slots) return KE_ERROR_OUT_OF_MEMORY;
    memset(new_slots, 0, new_capacity * sizeof(slot));

    t->slots = new_slots;
    t->capacity = new_capacity;
    t->occupied = 0;
    t->active = 0;

    for (size_t i = 0; i < old_cap; i++) {
        const slot *s = &old_slots[i];
        if (s->key == RC_EMPTY || s->key == RC_TOMBSTONE) continue;
        bool found = false;
        size_t idx = table_probe(t, s->key, &found);
        t->slots[idx] = *s;
        t->occupied++;
        t->active++;
    }
    t->allocator->free(t->allocator, old_slots);
    return KE_OK;
}

static uint64_t key_from_handle(ke_resource_handle h) {
    return (uint64_t)h + 1ULL;  // +1 keeps 0 reserved for EMPTY
}

static uint64_t key_from_path(const char *path) {
    uint64_t k = ke_hash_string(path);
    if (k == RC_EMPTY)     return 1ULL;
    if (k == RC_TOMBSTONE) return RC_TOMBSTONE - 1ULL;
    return k;
}

// ── vtable: lifetime ────────────────────────────────────────────────────────

static ke_result vt_register(ke_resource_cache *self, ke_resource_handle handle) {
    if (!self || handle == KE_RESOURCE_HANDLE_NONE) return KE_ERROR_INVALID_ARGUMENT;
    rc_state *s = (rc_state *)self->handle;

    ke_result rc = table_reserve(&s->resources);
    if (rc != KE_OK) return rc;

    bool found = false;
    uint64_t key = key_from_handle(handle);
    size_t idx = table_probe(&s->resources, key, &found);
    if (found) return KE_ERROR_INVALID_ARGUMENT;  // double-register

    if (s->resources.slots[idx].key == RC_EMPTY) s->resources.occupied++;
    s->resources.active++;
    s->resources.slots[idx].key      = key;
    s->resources.slots[idx].refcount = 1;
    s->resources.slots[idx].handle   = handle;
    return KE_OK;
}

static ke_result vt_retain(ke_resource_cache *self, ke_resource_handle handle) {
    if (!self || handle == KE_RESOURCE_HANDLE_NONE) return KE_ERROR_INVALID_ARGUMENT;
    rc_state *s = (rc_state *)self->handle;
    bool found = false;
    size_t idx = table_probe(&s->resources, key_from_handle(handle), &found);
    if (!found) return KE_ERROR_NOT_FOUND;
    s->resources.slots[idx].refcount++;
    return KE_OK;
}

// Walks the path table and tombstones any entry pointing at `handle`. Called
// from release() when refcount hits zero so dedup cache stays consistent.
static void evict_paths_for_handle(rc_state *s, ke_resource_handle handle) {
    for (size_t i = 0; i < s->paths.capacity; i++) {
        slot *p = &s->paths.slots[i];
        if (p->key != RC_EMPTY && p->key != RC_TOMBSTONE && p->handle == handle) {
            p->key = RC_TOMBSTONE;
            s->paths.active--;
        }
    }
}

static ke_result vt_release(ke_resource_cache *self, ke_resource_handle handle) {
    if (!self || handle == KE_RESOURCE_HANDLE_NONE) return KE_ERROR_INVALID_ARGUMENT;
    rc_state *s = (rc_state *)self->handle;
    bool found = false;
    size_t idx = table_probe(&s->resources, key_from_handle(handle), &found);
    if (!found) return KE_ERROR_NOT_FOUND;

    slot *slot_ref = &s->resources.slots[idx];
    if (slot_ref->refcount == 0) return KE_ERROR_INVALID_ARGUMENT;
    slot_ref->refcount--;
    if (slot_ref->refcount > 0) return KE_OK;

    slot_ref->key = RC_TOMBSTONE;
    slot_ref->refcount = 0;
    s->resources.active--;

    evict_paths_for_handle(s, handle);

    if (s->destroy_fn) s->destroy_fn(handle, s->destroy_ctx);
    return KE_OK;
}

// ── vtable: path cache ──────────────────────────────────────────────────────

static bool vt_try_get_cached(ke_resource_cache *self, const char *key, ke_resource_handle *out_handle) {
    if (!self || !key || !out_handle) return false;
    rc_state *s = (rc_state *)self->handle;
    bool found = false;
    size_t idx = table_probe(&s->paths, key_from_path(key), &found);
    if (!found) return false;

    ke_resource_handle h = s->paths.slots[idx].handle;
    // Retain on behalf of caller. If the underlying resource vanished
    // (stale path entry), drop the path entry and report cache miss.
    if (vt_retain(self, h) != KE_OK) {
        s->paths.slots[idx].key = RC_TOMBSTONE;
        s->paths.active--;
        return false;
    }
    *out_handle = h;
    return true;
}

static ke_result vt_cache_insert(ke_resource_cache *self, const char *key, ke_resource_handle handle) {
    if (!self || !key || handle == KE_RESOURCE_HANDLE_NONE) return KE_ERROR_INVALID_ARGUMENT;
    rc_state *s = (rc_state *)self->handle;
    ke_result rc = table_reserve(&s->paths);
    if (rc != KE_OK) return rc;

    bool found = false;
    uint64_t k = key_from_path(key);
    size_t idx = table_probe(&s->paths, k, &found);
    if (found) return KE_ERROR_INVALID_ARGUMENT;  // duplicate key — caller must try_get_cached first

    if (s->paths.slots[idx].key == RC_EMPTY) s->paths.occupied++;
    s->paths.active++;
    s->paths.slots[idx].key      = k;
    s->paths.slots[idx].refcount = 0;
    s->paths.slots[idx].handle   = handle;
    return KE_OK;
}

static void vt_cache_evict(ke_resource_cache *self, const char *key) {
    if (!self || !key) return;
    rc_state *s = (rc_state *)self->handle;
    bool found = false;
    size_t idx = table_probe(&s->paths, key_from_path(key), &found);
    if (!found) return;
    s->paths.slots[idx].key = RC_TOMBSTONE;
    s->paths.active--;
}

// ── vtable: teardown ────────────────────────────────────────────────────────

static void vt_destroy(ke_resource_cache *self) {
    if (!self) return;
    rc_state *s = (rc_state *)self->handle;
    if (!s) return;

    // Fire destroy callback for every resource still alive.
    for (size_t i = 0; i < s->resources.capacity; i++) {
        slot *r = &s->resources.slots[i];
        if (r->key == RC_EMPTY || r->key == RC_TOMBSTONE) continue;
        ke_resource_handle h = r->handle;
        r->key = RC_TOMBSTONE;
        if (s->destroy_fn) s->destroy_fn(h, s->destroy_ctx);
    }

    table_destroy(&s->resources);
    table_destroy(&s->paths);
    ke_allocator *a = s->allocator;
    a->free(a, s);
    a->destroy(a);
}

// ── Factory ─────────────────────────────────────────────────────────────────

ke_result ke_resource_cache_create(const ke_resource_cache_params *params,
                                    ke_resource_cache             **out_cache) {
    if (!params || !out_cache) return KE_ERROR_INVALID_ARGUMENT;

    ke_allocator *a = ke_allocator_malloc_create();
    if (!a) return KE_ERROR_OUT_OF_MEMORY;

    rc_state *s = (rc_state *)a->alloc(a, sizeof(rc_state), alignof(rc_state));
    if (!s) { a->destroy(a); return KE_ERROR_OUT_OF_MEMORY; }
    memset(s, 0, sizeof(*s));

    s->allocator   = a;
    s->destroy_fn  = params ? params->destroy_fn  : NULL;
    s->destroy_ctx = params ? params->destroy_ctx : NULL;

    ke_result rc = table_init(&s->resources, a, 64);
    if (rc != KE_OK) { a->free(a, s); a->destroy(a); return rc; }
    rc = table_init(&s->paths, a, 64);
    if (rc != KE_OK) { table_destroy(&s->resources); a->free(a, s); a->destroy(a); return rc; }

    s->api.handle            = s;
    s->api.register_resource = vt_register;
    s->api.retain            = vt_retain;
    s->api.release           = vt_release;
    s->api.try_get_cached    = vt_try_get_cached;
    s->api.cache_insert      = vt_cache_insert;
    s->api.cache_evict       = vt_cache_evict;
    s->api.destroy           = vt_destroy;

    *out_cache = &s->api;
    return KE_OK;
}
