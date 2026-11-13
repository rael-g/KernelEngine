#ifndef KERNEL_ENGINE_ECS_KE_ECS_FLECS_H_
#define KERNEL_ENGINE_ECS_KE_ECS_FLECS_H_

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

/// Creates a ke_ecs vtable backed by an internally-owned world.
/// Also installs process-wide log and abort handlers: a check flecs fails makes the
/// slot that called it return KE_RESULT_INVALID_ARGUMENT, and an internal failure of
/// flecs logs flecs's message and the stack before flecs ends the process.
/// @param config [borrowed] Required; every field is read as given.
/// @param out_ecs [out] Receives the ECS; left zeroed on failure.
/// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p out_ecs or a reserved_id_capacity that leaves
///         no reserve pool; KE_RESULT_OUT_OF_MEMORY; KE_RESULT_NOT_INITIALIZED when flecs cannot
///         start the world.
KE_ECS_FLECS_API ke_result ke_ecs_flecs_create(const ke_ecs_config *config,
                                               ke_ecs_handle             *out_ecs);

#ifdef __cplusplus
}
#endif

#endif
