#ifndef KERNEL_ENGINE_FRAMEWORK_RESOURCE_CACHE_H_
#define KERNEL_ENGINE_FRAMEWORK_RESOURCE_CACHE_H_

// ke_resource_cache — language-agnostic resource lifecycle contract (Tier S — S6).
//
// GPU resource handles are plain uint32_t values (ke_resource_handle). Any language binding
// that creates a resource registers it here; other bindings (Lua, C++, C#) can then
// retain/release the same resource through this contract without re-implementing ref-counting.
//
// Caching (path → handle) is also provided so multiple callers loading the same asset
// (e.g. Pong and a Lua menu loading the same texture) share a single GPU upload.

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/context/types.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef uint32_t ke_resource_handle;

#define KE_RESOURCE_HANDLE_NONE UINT32_MAX

    // Called when the reference count reaches zero; the implementation must free the GPU resource.
    typedef void (*ke_resource_destroy_func)(ke_resource_handle handle, void *ctx);

    typedef struct ke_resource_cache
    {
        void *handle; // opaque; owned by the implementation

        // ── Lifetime ──────────────────────────────────────────────────────────

        /// Registers a new resource with refcount = 1. destroy_fn is called (on the renderer thread)
        /// when the count reaches zero. Returns KE_ERROR_INVALID_ARGUMENT if handle == KE_RESOURCE_HANDLE_NONE.
        ke_result (*register_resource)(struct ke_resource_cache *self,
                                       ke_resource_handle         handle,
                                       ke_resource_destroy_func   destroy_fn,
                                       void                      *destroy_ctx);

        /// Increments the reference count. Returns KE_ERROR_NOT_FOUND if the handle is unknown.
        ke_result (*retain)(struct ke_resource_cache *self, ke_resource_handle handle);

        /// Decrements the reference count; fires destroy_fn when it reaches zero and removes the entry.
        ke_result (*release)(struct ke_resource_cache *self, ke_resource_handle handle);

        // ── Path-keyed cache (dedup) ──────────────────────────────────────────

        /// Returns true and sets *out_handle if the key is cached; also retains on behalf of the caller.
        bool (*try_get_cached)(struct ke_resource_cache *self,
                               const char               *key,
                               ke_resource_handle       *out_handle);

        /// Associates a handle with a string key for later dedup lookups.
        void (*cache_insert)(struct ke_resource_cache *self,
                             const char               *key,
                             ke_resource_handle        handle);

        /// Removes a cached key (called automatically via the destroy hook when refcount → 0).
        void (*cache_evict)(struct ke_resource_cache *self, const char *key);

        void (*destroy)(struct ke_resource_cache *self);

    } ke_resource_cache;

    // Factory `ke_resource_cache_create()` lives in the default plugin
    // (`src/cpp/framework/resource_cache/`), declared in
    // <kernel_engine/framework/resource_cache_create.h>.

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_RESOURCE_CACHE_H_
