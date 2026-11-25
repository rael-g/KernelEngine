#ifndef KERNEL_ENGINE_ECS_ECS_FLECS_PARTS_H_
#define KERNEL_ENGINE_ECS_ECS_FLECS_PARTS_H_

#include <kernel_engine/ecs/ke_ecs_flecs.h>
#include <kernel_engine/assembly/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_ecs_flecs contains: `ecs_flecs`, providing ke_ecs.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_ECS_FLECS_API const ke_part *ke_ecs_flecs_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
