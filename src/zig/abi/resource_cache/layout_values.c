#include <stddef.h>
#include <kernel_engine/resource_cache/resource_cache.h>
const unsigned long long layout_values[] = {
    sizeof(ke_resource_cache_params),
    offsetof(ke_resource_cache_params, destroy_fn),
    offsetof(ke_resource_cache_params, destroy_ctx),
    sizeof(ke_resource_cache),
    offsetof(ke_resource_cache, handle),
    offsetof(ke_resource_cache, register_resource),
    offsetof(ke_resource_cache, retain),
    offsetof(ke_resource_cache, release),
    offsetof(ke_resource_cache, try_get_cached),
    offsetof(ke_resource_cache, cache_insert),
    offsetof(ke_resource_cache, cache_evict),
    sizeof(ke_resource_cache_handle),
    offsetof(ke_resource_cache_handle, ref),
    offsetof(ke_resource_cache_handle, destroy),
    0,
};
