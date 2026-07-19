#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_CREATE_H_

#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/ecs/ke_ecs.h>

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
    /// are picked up via component_lookup). Returns the tree via out_tree;
    /// caller invokes tree->destroy(tree) when done.
    KE_FRAMEWORK_API ke_scene_tree_handle ke_scene_tree_create(
        ke_ecs    *ecs,
        ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_CREATE_H_
