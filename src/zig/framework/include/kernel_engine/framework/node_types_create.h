#ifndef KERNEL_ENGINE_FRAMEWORK_NODE_TYPES_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_NODE_TYPES_CREATE_H_

#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/framework/input_actions.h>
#include <kernel_engine/framework/node_types.h>
#include <kernel_engine/framework/scene_tree.h>
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

    /// Creates the node types of `ecs`, whose behaviours run as systems of `runtime`, whose
    /// nodes live in `scene_tree` and whose axis and pressed read `input_actions`. Registers the
    /// component that marks a node readied, and the system that clears the events at PreUpdate.
    /// `runtime`, `ecs`, `scene_tree` and `input_actions` must outlive the node types, whose
    /// destroy unregisters every system they registered.
    /// @param input_actions [borrowed,optional] Without it, axis answers 0 and pressed false.
    /// @param out_types [out] Receives the node types; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p runtime, @p ecs, @p scene_tree or
    ///         @p out_types, KE_RESULT_OUT_OF_MEMORY, or the code of the ecs or the runtime that
    ///         refused.
    KE_FRAMEWORK_API ke_result ke_node_types_create(
        ke_runtime           *runtime,
        ke_ecs               *ecs,
        ke_scene_tree        *scene_tree,
        ke_input_actions     *input_actions,
        ke_node_types_handle *out_types);

#ifdef __cplusplus
}
#endif

#endif
