#ifndef KERNEL_ENGINE_KERNEL_WORLD_KE_ECS_FLECS_H_
#define KERNEL_ENGINE_KERNEL_WORLD_KE_ECS_FLECS_H_

// ke_ecs_flecs — flecs-backed implementation of the ke_ecs contract.
//
// The flecs build linked by this plugin strips the pipeline / system / timer
// addons. flecs is used as storage + queries + observers only; the scheduler
// is the in-house ke_runtime (see kernel/runtime/runtime_create.h).

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/world/ke_ecs.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_ecs_flecs_params
{
    int reserved;  // empty for the spike; expanded as the surface grows
} ke_ecs_flecs_params;

/// Creates a ke_ecs vtable backed by an internally-owned flecs world.
/// Ownership: the caller owns the returned ke_ecs*; call ke_ecs->destroy() when done.
KE_API ke_result ke_ecs_flecs_create(ke_allocator              *alloc,
                                      const ke_ecs_flecs_params *params,
                                      ke_ecs                   **out_ecs);

#ifdef __cplusplus
}
#endif

#endif  // KERNEL_ENGINE_KERNEL_WORLD_KE_ECS_FLECS_H_
