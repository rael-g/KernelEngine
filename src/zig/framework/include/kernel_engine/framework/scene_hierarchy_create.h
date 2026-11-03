#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_HIERARCHY_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_HIERARCHY_CREATE_H_

#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/framework/scene_hierarchy.h>
#include <kernel_engine/runtime/runtime.h>

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

    /// Registers the hierarchy flattening and transform propagation systems
    /// against `runtime`, reading the scene graph out of `ecs`. The
    /// transform/hierarchy components are resolved by the names a scene_tree
    /// already registers them under, so a scene_tree must exist on this ecs
    /// first; creating a hierarchy without one fails as not found. `runtime` must
    /// outlive the hierarchy, whose destroy unregisters what it registered.
    /// @param out_hierarchy [out] Receives the hierarchy; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument, KE_RESULT_NOT_FOUND,
    ///         KE_RESULT_OUT_OF_MEMORY, or the code of the runtime that refused the system.
    KE_FRAMEWORK_API ke_result ke_scene_hierarchy_create(
        ke_runtime                *runtime,
        ke_ecs                    *ecs,
        ke_scene_hierarchy_handle *out_hierarchy);

#ifdef __cplusplus
}
#endif

#endif
