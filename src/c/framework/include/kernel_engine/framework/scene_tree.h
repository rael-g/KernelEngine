#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_H_

// ke_scene_tree — minimal language-agnostic scene graph contract (Tier S — S7).
//
// Only universal operations are promoted: root entity access, node destruction
// (post-order: children before parents), and path-based node lookup.
//
// Lifecycle tick_* methods (awake/start/update/late_update) are intentionally
// absent: native bindings (Lua, C++) drive lifecycle through the ke_script_component
// callbacks dispatched by the C ScriptSystem (S1). The tick_* walks in Tree.cs are
// C#-specific because they call Node.Tick* managed methods.
//
// The C# Framework provides CSharpSceneTree as the round-trip implementation.
// A future C++ plugin could provide the same contract without managed overhead.

#include <kernel_engine/framework/types.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/world/ecs.h>  // ke_entity
struct ke_world;

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_scene_tree
    {
        void *handle; // opaque; owned by the implementation

        /// Returns the root entity. Always valid for the lifetime of the tree.
        ke_entity (*root)(struct ke_scene_tree *self);

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

    // ── Factory ───────────────────────────────────────────────────────────────

    /// Allocates a default ke_scene_tree backed by the given world. The factory
    /// creates the root entity (with hierarchy + name components attached) and
    /// stores it as the tree's anchor; root() always returns it. Subsequent
    /// children must be created by the caller and parented under root via
    /// ke_hierarchy_component (the same way a binding would attach any node).
    KE_FRAMEWORK_API ke_result ke_scene_tree_create(
        struct ke_world  *world,
        ke_allocator     *alloc,
        ke_scene_tree   **out_tree);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_H_
