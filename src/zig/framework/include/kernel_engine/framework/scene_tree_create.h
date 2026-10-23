#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_CREATE_H_

#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/ecs/ke_ecs.h>
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

    /// Creates a scene_tree backed by the supplied ecs. Registers the
    /// transform/hierarchy/name components by name (idempotent — if a previous
    /// scene_tree on the same ecs already registered them, the existing cids
    /// are reused).
    /// `runtime` may be NULL, in which case no systems are registered and the
    /// caller is responsible for calling propagate_transforms itself. Passing one
    /// registers the hierarchy maintenance that keeps world matrices current.
    /// @param out_tree [out] Receives the tree; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p ecs or @p out_tree,
    ///         KE_RESULT_OUT_OF_MEMORY, or the code of the ecs or the runtime that refused.
    KE_FRAMEWORK_API ke_result ke_scene_tree_create(
        ke_ecs               *ecs,
        ke_runtime           *runtime,
        ke_scene_tree_handle *out_tree);

#ifdef __cplusplus
}
#endif

#endif
