#ifndef KERNEL_ENGINE_FRAMEWORK_WORLD_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_WORLD_CREATE_H_

#include <kernel_engine/framework/world.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_FRAMEWORK_API
#if defined(_WIN32) || defined(__CYGWIN__)
#ifdef KE_FRAMEWORK_STATIC
#define KE_FRAMEWORK_API
#else
#ifdef KE_FRAMEWORK_EXPORT
#define KE_FRAMEWORK_API __declspec(dllexport)
#else
#define KE_FRAMEWORK_API __declspec(dllimport)
#endif
#endif
#else
#define KE_FRAMEWORK_API __attribute__((visibility("default")))
#endif
#endif

    /// Creates a world over the params' ecs and runtime, registering the transform, 2D transform
    /// and world transform components on the ecs.
    /// @param out_world [out] Receives the world; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p params, ecs, runtime or
    ///         @p out_world, KE_RESULT_OUT_OF_MEMORY, or the code of the ecs that refused a
    ///         component.
    KE_FRAMEWORK_API ke_result ke_world_create(
        const ke_world_params *params, ke_world_handle *out_world);

#ifdef __cplusplus
}
#endif

#endif
