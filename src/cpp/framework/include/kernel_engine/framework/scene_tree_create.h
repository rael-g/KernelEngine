#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_CREATE_H_

#include <kernel_engine/kernel/framework/scene_tree.h>

#ifdef __cplusplus
extern "C"
{
#endif

    KE_FRAMEWORK_API ke_result ke_scene_tree_create(
        struct ke_world  *world,
        ke_allocator     *alloc,
        ke_scene_tree   **out_tree);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_CREATE_H_
