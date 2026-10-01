#ifndef KERNEL_ENGINE_RESOURCE_CACHE_RESOURCE_CACHE_H_
#define KERNEL_ENGINE_RESOURCE_CACHE_RESOURCE_CACHE_H_

#include <kernel_engine/common/error.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef uint32_t ke_resource_handle;

#define KE_RESOURCE_HANDLE_NONE UINT32_MAX

    /// Per-cache destroy callback: called once per resource when its refcount
    /// reaches zero (or once during destroy() for every still-live resource).
    typedef void (*ke_resource_destroy_func)(ke_resource_handle handle, void *ctx);

    typedef struct ke_resource_cache_params
    {
        ke_resource_destroy_func  destroy_fn;    ///< invoked on refcount → 0 (and on destroy of still-live entries); may be NULL
        void                     *destroy_ctx;   ///< forwarded to destroy_fn unchanged
    } ke_resource_cache_params;

    typedef struct ke_resource_cache
    {
        void *handle;

        /// Registers a new resource with refcount = 1. Returns KE_ERROR_INVALID_ARGUMENT
        /// if handle == KE_RESOURCE_HANDLE_NONE or if already registered.
        bool (*register_resource)(struct ke_resource_cache *self,
                                  ke_resource_handle         handle,
                                  ke_error                 **out_error);

        /// Increments the reference count. Sets out_error to KE_ERROR_NOT_FOUND if the handle is unknown.
        bool (*retain)(struct ke_resource_cache *self, ke_resource_handle handle, ke_error **out_error);

        /// Decrements the reference count; fires the cache's destroy_fn when it reaches zero
        /// and removes the entry.
        bool (*release)(struct ke_resource_cache *self, ke_resource_handle handle, ke_error **out_error);

        /// Returns true and sets *out_handle if the key is cached; also retains on behalf of the caller.
        bool (*try_get_cached)(struct ke_resource_cache *self,
                               const char               *key,
                               ke_resource_handle       *out_handle);

        /// Associates a handle with a string key for later dedup lookups. Returns
        /// KE_ERROR_INVALID_ARGUMENT if the key is already mapped (callers should
        /// try_get_cached first to detect intentional re-insertion).
        bool (*cache_insert)(struct ke_resource_cache *self,
                             const char               *key,
                             ke_resource_handle        handle,
                             ke_error                **out_error);

        /// Removes a cached key (called automatically when refcount → 0).
        void (*cache_evict)(struct ke_resource_cache *self, const char *key);

    } ke_resource_cache;

    typedef struct ke_resource_cache_handle
    {
        ke_resource_cache *ref;
        void (*destroy)(ke_resource_cache *self);
    } ke_resource_cache_handle;

#ifdef __cplusplus
}
#endif

#endif
