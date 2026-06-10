#ifndef KERNEL_ENGINE_KERNEL_RUNTIME_RUNTIME_CREATE_H_
#define KERNEL_ENGINE_KERNEL_RUNTIME_RUNTIME_CREATE_H_

// ke_runtime_create — the in-house scheduler.
// Owns the system catalog + phase loop + (eventually) parallel wave dispatch.
// Storage is borrowed via ke_ecs*; the scheduler never owns it.

#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/runtime/runtime.h>
#include <kernel_engine/kernel/world/ke_ecs.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_runtime_params {
    int reserved;  // empty for the spike; expanded with phase config + logger in R2.5c
} ke_runtime_params;

KE_API ke_result ke_runtime_create(ke_allocator           *alloc,
                                    ke_ecs                 *ecs,
                                    const ke_runtime_params *params,
                                    ke_runtime            **out_runtime);

#ifdef __cplusplus
}
#endif

#endif  // KERNEL_ENGINE_KERNEL_RUNTIME_RUNTIME_CREATE_H_
