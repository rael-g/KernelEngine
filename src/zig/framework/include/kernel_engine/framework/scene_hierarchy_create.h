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
    /// first; creating a hierarchy without one is an error rather than a silent
    /// no-op, since every later tick would quietly leave world matrices stale.
    KE_FRAMEWORK_API ke_scene_hierarchy_handle ke_scene_hierarchy_create(
        ke_runtime *runtime,
        ke_ecs     *ecs,
        ke_error  **out_error);

#ifdef __cplusplus
}
#endif

#endif
