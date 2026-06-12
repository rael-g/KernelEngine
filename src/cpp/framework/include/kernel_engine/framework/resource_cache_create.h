#ifndef KERNEL_ENGINE_FRAMEWORK_RESOURCE_CACHE_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_RESOURCE_CACHE_CREATE_H_

#include <kernel_engine/kernel/framework/resource_cache.h>

#ifdef __cplusplus
extern "C"
{
#endif

    KE_FRAMEWORK_API ke_result ke_resource_cache_create(
        ke_allocator       *alloc,
        ke_resource_cache **out_cache);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_RESOURCE_CACHE_CREATE_H_
