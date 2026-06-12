#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_H_

// ke_scene_tree — minimal language-agnostic scene graph contract (Tier S — S7).
//
// Only universal operations are promoted: root entity access, node creation,
// node destruction (post-order: children before parents), and path-based
// node lookup. The framework's opinion about "every scene node has Transform
// + Hierarchy + Name components" lives here.
//
// scene_tree owns the cids of its three components (transform/hierarchy/name),
// registering them with the supplied ke_ecs at create time. Component PODs
// are declared in kernel/framework/components.h; game code attaches/reads
// them via ke_ecs->component_get/add.

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/ecs/ecs.h>  // ke_entity
#include <kernel_engine/kernel/framework/components.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_scene_tree
    {
        void *handle; // opaque; owned by the implementation

        /// Returns the root entity. Always valid for the lifetime of the tree.
        ke_entity (*root)(struct ke_scene_tree *self);

        /// Creates a new node attached under `parent` (KE_ENTITY_INVALID = root).
        /// Initialises Transform (origin, identity rotation, unit scale), Hierarchy
        /// (prepended into the parent's child list — O(1)), and Name. Returns the
        /// new entity, or KE_ENTITY_INVALID on failure. `name` may be NULL/empty.
        ke_entity (*create_node)(struct ke_scene_tree *self, const char *name, ke_entity parent);

        /// Destroys a node and all its descendants. Fires on_destroy callbacks in
        /// post-order (children before parents). After this call the entity must not
        /// be used. Returns KE_ERROR_NOT_FOUND if the entity is not part of this tree.
        ke_result (*destroy_node)(struct ke_scene_tree *self, ke_entity entity);

        /// Destroys all nodes. Called on application shutdown. Does NOT release ECS
        /// entities because the world is also going away; it only fires on_destroy hooks.
        void (*destroy_all)(struct ke_scene_tree *self);

        /// Resolves a node by name or path. Accepts:
        ///   - "Name"          — recursive pre-order search from root (first match).
        ///   - "/Path/Child"   — absolute path, segment by segment from root.
        /// Returns KE_ENTITY_INVALID when not found.
        ke_entity (*find_node)(struct ke_scene_tree *self, const char *name_or_path);

        void (*destroy)(struct ke_scene_tree *self);

    } ke_scene_tree;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_H_
