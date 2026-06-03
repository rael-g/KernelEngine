#ifndef KERNEL_ENGINE_FRAMEWORK_RESOURCE_CACHE_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_RESOURCE_CACHE_CREATE_H_

// Factory for the default ke_resource_cache implementation — tombstone-based
// open-addressing tables for the handle refcount map and the path dedup map.
// Single-threaded; the caller serializes Retain/Release.

#include <kernel_engine/framework/resource_cache.h>
#include <kernel_engine/framework/resource_cache_export.h>

#ifdef __cplusplus
extern "C"
{
#endif

    KE_RESOURCE_CACHE_API ke_result ke_resource_cache_create(
        ke_allocator       *alloc,
        ke_resource_cache **out_cache);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_RESOURCE_CACHE_CREATE_H_
