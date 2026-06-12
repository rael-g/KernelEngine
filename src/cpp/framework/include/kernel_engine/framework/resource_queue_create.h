#ifndef KERNEL_ENGINE_FRAMEWORK_RESOURCE_QUEUE_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_RESOURCE_QUEUE_CREATE_H_

#include <kernel_engine/kernel/framework/resource_queue.h>

#ifdef __cplusplus
extern "C"
{
#endif

    KE_FRAMEWORK_API ke_result ke_resource_queue_create(
        ke_allocator       *alloc,
        ke_resource_queue **out);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_RESOURCE_QUEUE_CREATE_H_
