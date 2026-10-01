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

KE_RESOURCE_CACHE_DEFAULT_API ke_resource_cache_handle ke_resource_cache_create(
    const ke_resource_cache_params *params,
    ke_error                       **out_error);

#ifdef __cplusplus
}
#endif

#endif
