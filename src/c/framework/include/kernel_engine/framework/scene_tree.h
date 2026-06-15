#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/framework/components.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_scene_tree
    {
        void *handle;

        ke_entity (*root)(struct ke_scene_tree *self);

        ke_entity (*create_node)(struct ke_scene_tree *self, const char *name, ke_entity parent);

        ke_result (*destroy_node)(struct ke_scene_tree *self, ke_entity entity);

        void (*destroy_all)(struct ke_scene_tree *self);

        ke_entity (*find_node)(struct ke_scene_tree *self, const char *name_or_path);

        void (*propagate_transforms)(struct ke_scene_tree *self);

        void (*destroy)(struct ke_scene_tree *self);

    } ke_scene_tree;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_H_
