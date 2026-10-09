#ifndef KERNEL_ENGINE_ECS_KE_ECS_FLECS_H_
#define KERNEL_ENGINE_ECS_KE_ECS_FLECS_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <stdint.h>

#ifndef KE_ECS_FLECS_API
#  if defined(_WIN32) || defined(__CYGWIN__)
#    ifdef KE_ECS_FLECS_STATIC
#      define KE_ECS_FLECS_API
#    elif defined(KE_ECS_FLECS_EXPORT)
#      define KE_ECS_FLECS_API __declspec(dllexport)
#    else
#      define KE_ECS_FLECS_API __declspec(dllimport)
#    endif
#  else
#    define KE_ECS_FLECS_API __attribute__((visibility("default")))
#  endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_ecs_flecs_params
{
    /// First id the world's own allocator may issue. Ids below it form the pool
    /// entity_reserve draws from, so this doubles as that pool's capacity — the
    /// world's own side is unbounded. 0 takes the default. Raise it for a world
    /// whose systems spawn heavily; entity_reserve returns 0 once it is spent.
    uint32_t world_id_base;
} ke_ecs_flecs_params;

/// Creates a ke_ecs vtable backed by an internally-owned world.
/// Also installs process-wide log and abort handlers: an internal assertion
/// failure in the world ends the process through ke_error_fatal, with a
/// readable message, and does not return.
KE_ECS_FLECS_API ke_ecs_handle ke_ecs_flecs_create(const ke_ecs_flecs_params *params,
                                                   ke_error                 **out_error);

#ifdef __cplusplus
}
#endif

#endif
