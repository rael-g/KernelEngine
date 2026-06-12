#ifndef KERNEL_ENGINE_FRAMEWORK_COMPONENTS_H_
#define KERNEL_ENGINE_FRAMEWORK_COMPONENTS_H_

// Framework component vocabulary — POD structs the framework registers with
// ke_ecs and that game code attaches to entities. These are the OPINIONS the
// framework brings: "a scene has transform/hierarchy/name on every node,
// cameras have fov, lights have direction, meshes have a handle". An
// alternative framework implementation may declare a different vocabulary
// here (or skip parts of it).
//
// Components in this header are PURE DATA — no functions, no exports. The
// systems that read/write them live inside the framework plugin and are
// registered with the runtime when the framework is wired up.

#include <kernel_engine/kernel/common/math.h>  // ke_vec3, ke_quat, ke_mat4
#include <kernel_engine/kernel/ecs/ecs.h>      // ke_entity, KE_ENTITY_INVALID

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // ── Scene-graph components ───────────────────────────────────────────────

    /// Per-node 3D transform. World-space matrix is computed by the
    /// TransformSystem each tick and cached here for read-only use by
    /// downstream systems (CameraRenderSystem, MeshRenderSystem, ...).
    typedef struct ke_transform_component
    {
        ke_vec3 position;
        ke_quat rotation;
        ke_vec3 scale;
        ke_mat4 world_matrix;
    } ke_transform_component;

    /// Doubly-linked hierarchy: every node carries parent + a list head into
    /// children + sibling pointers. O(1) attach/detach during scene_tree
    /// operations.
    typedef struct ke_hierarchy_component
    {
        ke_entity parent;
        ke_entity first_child;
        ke_entity next_sibling;
        ke_entity prev_sibling;
    } ke_hierarchy_component;

    /// Fixed-capacity node name. 64 bytes including the NUL — handles most
    /// games without heap allocation.
    typedef struct ke_name_component
    {
        char name[64];
    } ke_name_component;

#define KE_COMPONENT_NAME_TRANSFORM "transform"
#define KE_COMPONENT_NAME_HIERARCHY "hierarchy"
#define KE_COMPONENT_NAME_NAME      "name"

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_COMPONENTS_H_
