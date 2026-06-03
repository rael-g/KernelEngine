#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_H_

#include <kernel_engine/framework/framework_export.h>
#include <kernel_engine/framework/node_type_registry.h>
#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
struct ke_world;

#ifdef __cplusplus
extern "C"
{
#endif

    // ── Scene loader contract ────────────────────────────────────────────────
    //
    // Language-agnostic vtable for loading a `.scene.toml` file into a world.
    // The default plugin (src/cpp/framework/) uses tomlplusplus to parse and
    // drives the supplied scene_tree + node_type_registry to instantiate nodes:
    //
    //     [[node]]
    //     name   = "Player"
    //     type   = "MeshNode"
    //     parent = "World"        # optional; defaults to root
    //     [node.transform]
    //     position       = [0, 1, 0]
    //     scale          = [1, 1, 1]
    //     rotation_euler = [0, 90, 0]   # degrees; ZYX order
    //     [node.properties]
    //     mesh = "res://primitives/cube"
    //
    // Property values are forwarded to the node type's set_property callback
    // as ke_variant — strings, ints, floats, bools, vec2/3/4, and quaternion
    // (rotation_euler is converted to a quaternion before dispatch).

    typedef struct ke_scene_loader
    {
        void *handle; // opaque; owned by the implementation

        /// Loads the scene file at the UTF-8 path into the world associated
        /// with this loader at construction time. Blocking — does not return
        /// until all nodes are created and all properties applied. Returns
        /// KE_ERROR_NOT_FOUND on a missing/unparseable file.
        ke_result (*load)(struct ke_scene_loader *self, const char *path);

        /// Releases resources owned by this loader. After destroy() the
        /// pointer must not be used.
        void (*destroy)(struct ke_scene_loader *self);
    } ke_scene_loader;

    // ── Factory ──────────────────────────────────────────────────────────────

    /// Allocates a scene loader bound to the given world / tree / registry.
    /// The loader does NOT take ownership of the inputs; the caller keeps them
    /// alive across all load() invocations.
    ///
    /// project_root may be NULL. When provided, nested scene paths starting with
    /// "res://" resolve to (project_root + remainder). When NULL, nested paths
    /// are resolved relative to the loading scene file's directory.
    KE_FRAMEWORK_API ke_result ke_scene_loader_create(
        ke_allocator           *alloc,
        struct ke_world        *world,
        ke_scene_tree          *tree,
        ke_node_type_registry  *registry,
        const char             *project_root,
        ke_scene_loader       **out_loader);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_H_
