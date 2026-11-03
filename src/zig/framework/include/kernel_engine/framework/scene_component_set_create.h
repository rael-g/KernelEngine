#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_COMPONENT_SET_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_COMPONENT_SET_CREATE_H_

#include <kernel_engine/framework/scene_component_set.h>

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

    /// Creates an empty scene component set, which the plugins fill through its `add` slot.
    /// @param out_set [out] Receives the set; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p out_set, or KE_RESULT_OUT_OF_MEMORY.
    KE_FRAMEWORK_API ke_result ke_scene_component_set_create(ke_scene_component_set_handle *out_set);

#ifdef __cplusplus
}
#endif

#endif
