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
#  ifdef KE_ECS_FLECS_STATIC
#    define KE_ECS_FLECS_API
#  elif defined(_WIN32) || defined(__CYGWIN__)
#    ifdef KE_ECS_FLECS_EXPORT
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

/// Error type for flecs internal fatal assertions (ke.ecs.flecs.fatal).
/// Parent: KE_ERROR_GENERAL. Used by ke_ecs vtable functions that intercept
/// flecs abort() calls via ecs_os_api.abort_ + setjmp/longjmp.
KE_ECS_FLECS_API extern const ke_error_type KE_ERROR_ECS_FLECS_FATAL;

/// Creates a ke_ecs vtable backed by an internally-owned flecs world.
/// Also installs process-wide ecs_os_api log + abort handlers so that flecs
/// assertions are translated to ke_error instead of calling abort().
KE_ECS_FLECS_API ke_result ke_ecs_flecs_create(const ke_ecs_flecs_params *params,
                                               ke_ecs_handle             *out_ecs,
                                               ke_error                 **out_error);

/// Returns the last flecs fatal message captured on the calling thread, or NULL
/// if no fatal occurred. Valid until the next ke_ecs vtable call on this thread.
KE_ECS_FLECS_API const char *ke_ecs_flecs_get_last_fatal_message(void);

#ifdef __cplusplus
}
#endif

#endif  // KERNEL_ENGINE_ECS_KE_ECS_FLECS_H_
