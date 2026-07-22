#ifndef KERNEL_ENGINE_ECS_KE_ECS_FLECS_H_
#define KERNEL_ENGINE_ECS_KE_ECS_FLECS_H_

// ke_ecs_flecs — flecs-backed implementation of the ke_ecs contract.
//
// The flecs build linked by this plugin strips the pipeline / system / timer
// addons. flecs is used as storage + queries + observers only; the scheduler
// is the in-house ke_runtime (see kernel/runtime/runtime_create.h).

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ke_ecs.h>

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
    int reserved;  // empty for the spike; expanded as the surface grows
} ke_ecs_flecs_params;

/// Creates a ke_ecs vtable backed by an internally-owned flecs world.
/// Also installs process-wide ecs_os_api log + abort handlers: flecs calls
/// abort() on an internal assertion failure, and the installed handler ends
/// the process through ke_error_fatal instead (readable message, no OS crash
/// dialog) rather than resuming — flecs offers no way to recover a world past
/// an internal assertion, so continuing would run against a world already
/// known to be broken.
KE_ECS_FLECS_API ke_ecs_handle ke_ecs_flecs_create(const ke_ecs_flecs_params *params,
                                                   ke_error                 **out_error);

#ifdef __cplusplus
}
#endif

#endif  // KERNEL_ENGINE_ECS_KE_ECS_FLECS_H_
