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

    // Forward declaration: a node created or destroyed from inside a running
    // system passes its ke_system_ctx so the structural change is deferred to the
    // wave barrier. Passing NULL performs the change immediately (scene load, setup).
    typedef struct ke_system_ctx ke_system_ctx;

    typedef struct ke_scene_tree
    {
        void *handle;

        ke_entity (*root)(struct ke_scene_tree *self);

        ke_entity (*create_node)(struct ke_scene_tree *self, const char *name, ke_entity parent, ke_system_ctx *ctx, ke_error **out_error);

        bool (*destroy_node)(struct ke_scene_tree *self, ke_entity entity, ke_system_ctx *ctx, ke_error **out_error);

        void (*destroy_all)(struct ke_scene_tree *self);

        ke_entity (*find_node)(struct ke_scene_tree *self, const char *name_or_path, ke_error **out_error);

        void (*propagate_transforms)(struct ke_scene_tree *self);


    } ke_scene_tree;

    typedef struct ke_scene_tree_handle
    {
        ke_scene_tree *ref;
        void (*destroy)(ke_scene_tree *self);
    } ke_scene_tree_handle;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_H_
