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

        /** The entity `entity` hangs from, or KE_ENTITY_INVALID when it is a root. */
        ke_entity (*parent)(struct ke_scene_tree *self, ke_entity entity);

        /**
         * The first of `entity`'s children, or KE_ENTITY_INVALID when it has none.
         * Paired with next_sibling this walks the child list a step at a time, which
         * is the shape parenthood already has: it is an intrusive list, so answering
         * with an array would mean building one on every call, and a caller after
         * just the first child would pay for all of them.
         */
        ke_entity (*first_child)(struct ke_scene_tree *self, ke_entity entity);

        /**
         * The next child of `entity`'s parent, or KE_ENTITY_INVALID at the end of the
         * list. Children come back in the order they were added.
         */
        ke_entity (*next_sibling)(struct ke_scene_tree *self, ke_entity entity);

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

#endif
