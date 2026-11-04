#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/commands.h>
#include <kernel_engine/framework/components.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_scene_tree
    {
        void *handle;

        /** [property] The tree's root entity. Valid for the whole lifetime of the tree. */
        ke_entity (*root)(struct ke_scene_tree *self);

        /**
         * Creates a node attached under `parent`, or under the root when `parent` is
         * KE_ENTITY_INVALID. The node exists when the call returns. Fails as an invalid argument
         * for a null tree or @p out_node, and as general when the ecs refuses the node.
         * @param name [utf8]
         * @param out_node [out] Receives the node.
         */
        ke_result (*create_node)(struct ke_scene_tree *self, const char *name, ke_entity parent, ke_entity *out_node);

        /**
         * Records the creation of a node into `commands`, with the same placement as
         * create_node. The id is usable as a reference at once; the node exists when
         * `commands` is applied. For a caller that may not touch the world, such as a
         * system body. Fails as an invalid argument for a null tree, @p commands or @p out_node,
         * and with the queue's code when it refuses the recording.
         * @param name [utf8]
         * @param commands
         * @param out_node [out] Receives the reserved id.
         */
        ke_result (*create_node_deferred)(struct ke_scene_tree *self, const char *name, ke_entity parent, ke_ecs_commands *commands, ke_entity *out_node);

        /**
         * Destroys a node and all its descendants, each child before its parent. The
         * node is gone when the call returns. Fails as an invalid argument for a null tree or the
         * invalid entity, and as not found for an entity that is not a node.
         */
        ke_result (*destroy_node)(struct ke_scene_tree *self, ke_entity entity);

        /**
         * Records the destruction of a node and its descendants into `commands`, as
         * destroy_node would do it when `commands` is applied. Fails as destroy_node does, as an
         * invalid argument for a null @p commands, and with the queue's code when it refuses the
         * recording.
         * @param commands
         */
        ke_result (*destroy_node_deferred)(struct ke_scene_tree *self, ke_entity entity, ke_ecs_commands *commands);

        /**
         * Destroys every child of the root and leaves the root. Keeps going past a subtree the ecs
         * refuses and returns the first failure.
         * @return KE_OK, or KE_RESULT_INVALID_ARGUMENT for a null self, the code of the first
         *         refused destroy, or KE_RESULT_NOT_FOUND when the root has no hierarchy.
         */
        ke_result (*destroy_all)(struct ke_scene_tree *self);

        /** The node a name or a slash-separated path from the root names, or KE_ENTITY_INVALID
         * when none does.
         * @param name_or_path [utf8] */
        ke_entity (*find_node)(struct ke_scene_tree *self, const char *name_or_path);

        /** The entity `entity` hangs from, or KE_ENTITY_INVALID when it is a root. */
        ke_entity (*parent)(struct ke_scene_tree *self, ke_entity entity);

        /**
         * The first of `entity`'s children, or KE_ENTITY_INVALID when it has none.
         * Paired with next_sibling this walks the child list one entry at a time.
         */
        ke_entity (*first_child)(struct ke_scene_tree *self, ke_entity entity);

        /**
         * The next child of `entity`'s parent, or KE_ENTITY_INVALID at the end of the
         * list. Children come back in the order they were added.
         */
        ke_entity (*next_sibling)(struct ke_scene_tree *self, ke_entity entity);

        void (*propagate_transforms)(struct ke_scene_tree *self);

        /**
         * Every node under the root, each node's children before the node and siblings in
         * the order they were linked, as many as the buffer holds. The root is not listed.
         * @param out_nodes [out,array_of:capacity] Receives the nodes; may be NULL when
         *        @p capacity is zero.
         * @param capacity Maximum number of nodes to write.
         * @return The number of nodes under the root, which exceeds @p capacity when the
         *         buffer was too small.
         */
        uint32_t (*children_first)(struct ke_scene_tree *self, ke_entity *out_nodes, uint32_t capacity);

        /**
         * A count that changes whenever a node is linked into or unlinked from the tree,
         * including when deferred commands apply. Two equal readings mean no parent link
         * changed between them.
         */
        uint64_t (*hierarchy_generation)(struct ke_scene_tree *self);

    } ke_scene_tree;

    /// [owner]
    typedef struct ke_scene_tree_handle
    {
        ke_scene_tree *ref;
        void (*destroy)(ke_scene_tree *self);
    } ke_scene_tree_handle;

#ifdef __cplusplus
}
#endif

#endif
