#ifndef KERNEL_ENGINE_RUNTIME_FLECS_H_
#define KERNEL_ENGINE_RUNTIME_FLECS_H_

#include <kernel_engine/kernel/runtime/runtime.h>
#include <kernel_engine/runtime/flecs/runtime_flecs_export.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_runtime_flecs_params {
    int reserved; // empty for the spike; expanded as the surface grows
} ke_runtime_flecs_params;

KE_RUNTIME_FLECS_API ke_result ke_runtime_flecs_create(
    ke_allocator                   *alloc,
    const ke_runtime_flecs_params  *params,
    ke_runtime                    **out_runtime);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RUNTIME_FLECS_H_
