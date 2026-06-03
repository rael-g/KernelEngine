#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_CREATE_H_

// Factory for the default ke_scene_tree implementation — a thin ECS-backed
// facade over hierarchy + name components. Creates the root entity at
// construction; everything else is walked through the world's registry.

#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/framework/scene_tree_export.h>

#ifdef __cplusplus
extern "C"
{
#endif

    KE_SCENE_TREE_API ke_result ke_scene_tree_create(
        struct ke_world  *world,
        ke_allocator     *alloc,
        ke_scene_tree   **out_tree);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_CREATE_H_
