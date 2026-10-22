#ifndef KERNEL_ENGINE_RESOURCE_CACHE_DEFAULT_RESOURCE_CACHE_DEFAULT_CREATE_H_
#define KERNEL_ENGINE_RESOURCE_CACHE_DEFAULT_RESOURCE_CACHE_DEFAULT_CREATE_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/resource_cache/resource_cache.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_RESOURCE_CACHE_DEFAULT_API
#  ifdef KE_RESOURCE_CACHE_DEFAULT_EXPORT
#    define KE_RESOURCE_CACHE_DEFAULT_API KE_EXPORT
#  else
#    define KE_RESOURCE_CACHE_DEFAULT_API KE_IMPORT
#  endif
#endif

/**
 * Creates a resource cache.
 * @param params [borrowed] The destroy callback and its context.
 * @param out_cache [out] Receives the cache; left zeroed on failure.
 * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for null @p params or @p out_cache, or
 *         KE_RESULT_OUT_OF_MEMORY.
 */
KE_RESOURCE_CACHE_DEFAULT_API ke_result ke_resource_cache_create(
    const ke_resource_cache_params *params,
    ke_resource_cache_handle       *out_cache);

#ifdef __cplusplus
}
#endif

#endif
