#include <kernel_engine/kernel/resource_cache/resource_cache.h>
#include <kernel_engine/framework/resource_cache_create.h>
#include <kernel_engine/kernel/common/hash.h>
#include <string.h>
#include <stdlib.h>

// ── Internal state ────────────────────────────────────────────────────────────
//
// Two parallel data structures:
//   (a) `entries[]` — open-addressed table of registered resources, keyed by
//       handle. Holds the refcount + destroy callback. Tombstones are tracked
//       so `release` can reclaim slots without breaking probe chains.
//   (b) `paths[]` — same shape, keyed by FNV hash of the path string. Maps
//       path → handle for dedup lookups. A path entry never owns a refcount
//       (the resource's own entry in (a) does).
//
// Open addressing + tombstones is enough for the current use case: tens of
// resources during gameplay, hundreds during scene load. If the working set
// grows, we can swap the body for the kernel ke_hash_map (which currently
// has no remove operation and would need the same tombstone logic added).

typedef struct slot
{
    uint64_t key;       // 0 = empty, UINT64_MAX = tombstone
    uint32_t refcount;  // resource entries only
    uint32_t handle;    // resource entries: redundant copy of key; path entries: target handle
    ke_resource_destroy_func destroy_fn;
    void                    *destroy_ctx;
} slot;

#define KE_RC_EMPTY     0ULL
#define KE_RC_TOMBSTONE UINT64_MAX

typedef struct table
{
    slot     *slots;
    size_t    capacity;  // power of two
    size_t    occupied;  // active + tombstones
    size_t    active;    // active only
    ke_allocator *allocator;
} table;

typedef struct ke_resource_cache_impl
{
    ke_resource_cache api;
    ke_allocator     *allocator;
    table             resources;  // handle → (refcount, destroy_fn, ctx)
    table             paths;      // hash(path) → handle
} ke_resource_cache_impl;

// ── Table ops ─────────────────────────────────────────────────────────────────

static ke_result table_init(table *t, ke_allocator *alloc, size_t initial_capacity)
{
    t->allocator = alloc;
    t->capacity  = initial_capacity;
    t->occupied  = 0;
    t->active    = 0;
    t->slots     = (slot *)alloc->alloc(alloc, initial_capacity * sizeof(slot), 0);
    if (!t->slots) return KE_ERROR_OUT_OF_MEMORY;
    memset(t->slots, 0, initial_capacity * sizeof(slot));
    return KE_OK;
}

static void table_destroy(table *t)
{
    if (t->slots && t->allocator) t->allocator->free(t->allocator, t->slots);
    t->slots = NULL;
    t->capacity = t->occupied = t->active = 0;
}

// Finds the slot index for `key`. Returns the index of an active entry
// matching the key, OR (if not found) the index of the first usable slot
// — preferring an earlier tombstone over a later empty slot so reinsertion
// keeps probe chains short. *out_found tells the caller which case it was.
static size_t table_probe(const table *t, uint64_t key, bool *out_found)
{
    size_t mask  = t->capacity - 1;
    size_t index = (size_t)(key & mask);
    size_t first_tombstone = SIZE_MAX;
    for (size_t i = 0; i < t->capacity; i++) {
        const slot *s = &t->slots[index];
        if (s->key == KE_RC_EMPTY) {
            *out_found = false;
            return (first_tombstone != SIZE_MAX) ? first_tombstone : index;
        }
        if (s->key == KE_RC_TOMBSTONE) {
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

// Reserves space for one more occupied slot (counts tombstones too — they
// pollute the probe distance even though they're not active). Triggers a
// rehash at load factor ≥ 0.7.
static ke_result table_reserve(table *t)
{
    if ((t->occupied + 1) * 10 < t->capacity * 7) return KE_OK;
    return table_rehash(t, t->capacity * 2);
}

static ke_result table_rehash(table *t, size_t new_capacity)
{
    slot *old_slots = t->slots;
    size_t old_cap = t->capacity;
    slot *new_slots = (slot *)t->allocator->alloc(t->allocator, new_capacity * sizeof(slot), 0);
    if (!new_slots) return KE_ERROR_OUT_OF_MEMORY;
    memset(new_slots, 0, new_capacity * sizeof(slot));

    t->slots = new_slots;
    t->capacity = new_capacity;
    t->occupied = 0;
    t->active = 0;

    for (size_t i = 0; i < old_cap; i++) {
        const slot *s = &old_slots[i];
        if (s->key == KE_RC_EMPTY || s->key == KE_RC_TOMBSTONE) continue;
        bool found = false;
        size_t idx = table_probe(t, s->key, &found);
        t->slots[idx] = *s;
        t->occupied++;
        t->active++;
    }
    t->allocator->free(t->allocator, old_slots);
    return KE_OK;
}

// Encodes a uint32_t handle as a non-empty/non-tombstone uint64_t key.
// `+1` reserves 0 (empty); we already exclude UINT32_MAX (= KE_RESOURCE_HANDLE_NONE)
// at the API boundary so the result is in [1, UINT32_MAX] — far from UINT64_MAX.
static inline uint64_t key_from_handle(ke_resource_handle h) { return (uint64_t)h + 1ULL; }

// Hashes a path into a 64-bit key, mapping the reserved sentinel values to a
// neighbouring bucket so they never appear as actual keys.
static inline uint64_t key_from_path(const char *path)
{
    uint64_t k = ke_hash_string(path);
    if (k == KE_RC_EMPTY) return 1ULL;
    if (k == KE_RC_TOMBSTONE) return KE_RC_TOMBSTONE - 1ULL;
    return k;
}

// ── vtable: lifetime ──────────────────────────────────────────────────────────

static ke_result rc_register(ke_resource_cache *self,
                             ke_resource_handle handle,
                             ke_resource_destroy_func destroy_fn,
                             void *destroy_ctx)
{
    if (!self || handle == KE_RESOURCE_HANDLE_NONE) return KE_ERROR_INVALID_ARGUMENT;
    ke_resource_cache_impl *impl = (ke_resource_cache_impl *)self->handle;

    ke_result rc = table_reserve(&impl->resources);
    if (rc != KE_OK) return rc;

    bool found = false;
    uint64_t key = key_from_handle(handle);
    size_t idx = table_probe(&impl->resources, key, &found);
    if (found) return KE_ERROR_INVALID_ARGUMENT; // double-register

    if (impl->resources.slots[idx].key == KE_RC_EMPTY) impl->resources.occupied++;
    impl->resources.active++;
    impl->resources.slots[idx] = (slot){
        .key = key,
        .refcount = 1,
        .handle = handle,
        .destroy_fn = destroy_fn,
        .destroy_ctx = destroy_ctx,
    };
    return KE_OK;
}

static ke_result rc_retain(ke_resource_cache *self, ke_resource_handle handle)
{
    if (!self || handle == KE_RESOURCE_HANDLE_NONE) return KE_ERROR_INVALID_ARGUMENT;
    ke_resource_cache_impl *impl = (ke_resource_cache_impl *)self->handle;
    bool found = false;
    size_t idx = table_probe(&impl->resources, key_from_handle(handle), &found);
    if (!found) return KE_ERROR_NOT_FOUND;
    impl->resources.slots[idx].refcount++;
    return KE_OK;
}

// Walks the path table and tombstones any entry pointing at `handle`. Called
// from release() so a resource freed by refcount=0 also disappears from the
// dedup cache. O(capacity) but the path table is small relative to other costs.
static void evict_paths_for_handle(ke_resource_cache_impl *impl, ke_resource_handle handle)
{
    for (size_t i = 0; i < impl->paths.capacity; i++) {
        slot *s = &impl->paths.slots[i];
        if (s->key != KE_RC_EMPTY && s->key != KE_RC_TOMBSTONE && s->handle == handle) {
            s->key = KE_RC_TOMBSTONE;
            impl->paths.active--;
        }
    }
}

static ke_result rc_release(ke_resource_cache *self, ke_resource_handle handle)
{
    if (!self || handle == KE_RESOURCE_HANDLE_NONE) return KE_ERROR_INVALID_ARGUMENT;
    ke_resource_cache_impl *impl = (ke_resource_cache_impl *)self->handle;
    bool found = false;
    size_t idx = table_probe(&impl->resources, key_from_handle(handle), &found);
    if (!found) return KE_ERROR_NOT_FOUND;

    slot *s = &impl->resources.slots[idx];
    if (s->refcount == 0) return KE_ERROR_INVALID_ARGUMENT; // shouldn't happen if active
    s->refcount--;
    if (s->refcount > 0) return KE_OK;

    // Snapshot destroy info before tombstoning the slot, then drop matching
    // paths from the dedup cache before invoking the destroy callback (so the
    // callback can't observe a stale cache entry).
    ke_resource_destroy_func fn = s->destroy_fn;
    void *ctx = s->destroy_ctx;
    s->key = KE_RC_TOMBSTONE;
    s->refcount = 0;
    s->destroy_fn = NULL;
    s->destroy_ctx = NULL;
    impl->resources.active--;

    evict_paths_for_handle(impl, handle);

    if (fn) fn(handle, ctx);
    return KE_OK;
}

// ── vtable: path cache ────────────────────────────────────────────────────────

static bool rc_try_get_cached(ke_resource_cache *self, const char *key, ke_resource_handle *out_handle)
{
    if (!self || !key || !out_handle) return false;
    ke_resource_cache_impl *impl = (ke_resource_cache_impl *)self->handle;
    bool found = false;
    size_t idx = table_probe(&impl->paths, key_from_path(key), &found);
    if (!found) return false;

    ke_resource_handle h = impl->paths.slots[idx].handle;
    // Retain on behalf of the caller. If the underlying resource is gone
    // (stale entry — shouldn't happen with evict_paths_for_handle, but defend
    // anyway), drop the path entry and report cache miss.
    if (rc_retain(self, h) != KE_OK) {
        impl->paths.slots[idx].key = KE_RC_TOMBSTONE;
        impl->paths.active--;
        return false;
    }
    *out_handle = h;
    return true;
}

static void rc_cache_insert(ke_resource_cache *self, const char *key, ke_resource_handle handle)
{
    if (!self || !key || handle == KE_RESOURCE_HANDLE_NONE) return;
    ke_resource_cache_impl *impl = (ke_resource_cache_impl *)self->handle;
    if (table_reserve(&impl->paths) != KE_OK) return;

    bool found = false;
    uint64_t k = key_from_path(key);
    size_t idx = table_probe(&impl->paths, k, &found);
    if (impl->paths.slots[idx].key == KE_RC_EMPTY) impl->paths.occupied++;
    if (!found) impl->paths.active++;
    impl->paths.slots[idx] = (slot){
        .key = k,
        .refcount = 0,
        .handle = handle,
        .destroy_fn = NULL,
        .destroy_ctx = NULL,
    };
}

static void rc_cache_evict(ke_resource_cache *self, const char *key)
{
    if (!self || !key) return;
    ke_resource_cache_impl *impl = (ke_resource_cache_impl *)self->handle;
    bool found = false;
    size_t idx = table_probe(&impl->paths, key_from_path(key), &found);
    if (!found) return;
    impl->paths.slots[idx].key = KE_RC_TOMBSTONE;
    impl->paths.active--;
}

// ── vtable: teardown ──────────────────────────────────────────────────────────

static void rc_destroy(ke_resource_cache *self)
{
    if (!self) return;
    ke_resource_cache_impl *impl = (ke_resource_cache_impl *)self->handle;
    if (!impl) return;

    // Fire destroy callbacks for any resources still alive — the cache is going
    // away, so its leases must too. Iterate a snapshot of indices: the callback
    // may not call back into the cache, but the slot is tombstoned anyway.
    for (size_t i = 0; i < impl->resources.capacity; i++) {
        slot *s = &impl->resources.slots[i];
        if (s->key == KE_RC_EMPTY || s->key == KE_RC_TOMBSTONE) continue;
        ke_resource_destroy_func fn = s->destroy_fn;
        void *ctx = s->destroy_ctx;
        ke_resource_handle h = s->handle;
        s->key = KE_RC_TOMBSTONE;
        if (fn) fn(h, ctx);
    }

    table_destroy(&impl->resources);
    table_destroy(&impl->paths);
    impl->allocator->free(impl->allocator, impl);
}

// ── Factory ───────────────────────────────────────────────────────────────────

ke_result ke_resource_cache_create(ke_allocator *alloc, ke_resource_cache **out_cache)
{
    if (!alloc || !out_cache) return KE_ERROR_INVALID_ARGUMENT;

    ke_resource_cache_impl *impl = (ke_resource_cache_impl *)alloc->alloc(
        alloc, sizeof(ke_resource_cache_impl), 0);
    if (!impl) return KE_ERROR_OUT_OF_MEMORY;
    memset(impl, 0, sizeof(*impl));
    impl->allocator = alloc;

    ke_result rc = table_init(&impl->resources, alloc, 64);
    if (rc != KE_OK) { alloc->free(alloc, impl); return rc; }
    rc = table_init(&impl->paths, alloc, 64);
    if (rc != KE_OK) { table_destroy(&impl->resources); alloc->free(alloc, impl); return rc; }

    impl->api = (ke_resource_cache){
        .handle           = impl,
        .register_resource = rc_register,
        .retain           = rc_retain,
        .release          = rc_release,
        .try_get_cached   = rc_try_get_cached,
        .cache_insert     = rc_cache_insert,
        .cache_evict      = rc_cache_evict,
        .destroy          = rc_destroy,
    };
    *out_cache = &impl->api;
    return KE_OK;
}
