#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/framework/components.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_system_ctx ke_system_ctx;

    typedef struct ke_scene_tree
    {
        void *handle;

        /** [idiom] Superseded by the managed Root property, same name. */
        ke_entity (*root)(struct ke_scene_tree *self);

        /** @param name [utf8] */
        ke_entity (*create_node)(struct ke_scene_tree *self, const char *name, ke_entity parent, ke_system_ctx *ctx, ke_error **out_error);

        bool (*destroy_node)(struct ke_scene_tree *self, ke_entity entity, ke_system_ctx *ctx, ke_error **out_error);

        void (*destroy_all)(struct ke_scene_tree *self);

        /** @param name_or_path [utf8] */
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
