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

#include <kernel_engine/kernel/common/handles.h>  // ke_mesh_handle, ke_material_handle
#include <kernel_engine/kernel/common/math.h>     // ke_vec3, ke_quat, ke_mat4
#include <kernel_engine/kernel/ecs/ecs.h>         // ke_entity, KE_ENTITY_INVALID

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

    // ── Render vocabulary ────────────────────────────────────────────────────
    //
    // Durable PODs that survive the deletion of the frame_packet extract path
    // in R6+. The current LEGACY render systems that wrote these into a
    // frame_packet have been removed; once R6 lands the per-component snapshot
    // mechanism, the render plugin reads these directly from the back buffer.

    typedef struct ke_camera_component
    {
        float   fov;
        float   near_plane;
        float   far_plane;
        float   orthographic_size;
        uint8_t orthographic; // 0 = perspective, non-zero = ortho
    } ke_camera_component;

    typedef struct ke_directional_light_component
    {
        float dir_x, dir_y, dir_z;
        float r, g, b;
        float intensity;
    } ke_directional_light_component;

    typedef struct ke_point_light_component
    {
        float radius;
        float r, g, b;
        float intensity;
    } ke_point_light_component;

    typedef struct ke_spot_light_component
    {
        float dir_x, dir_y, dir_z;
        float inner_angle;
        float outer_angle;
        float range;
        float r, g, b;
        float intensity;
    } ke_spot_light_component;

    /// Carries both resolved render handles AND the bake-request fields the
    /// SceneLoader writes from `[entity.components.mesh]`. The first frame an
    /// entity is seen with primitive[0] != '\0' and mesh handle == HANDLE_NONE,
    /// the framework's asset system bakes the primitive and assigns the handle
    /// (dedup'd by name + color). primitive stays in place as the canonical
    /// name so hot-reload re-bakes work.
    typedef struct ke_mesh_component
    {
        ke_mesh_handle     mesh;          ///< Resolved render handle (HANDLE_NONE = pending bake)
        ke_material_handle material;      ///< Resolved render handle (HANDLE_NONE = pending bake)
        char               primitive[32]; ///< Bake request (snake_case primitive name)
        float              color[4];      ///< RGBA tint; alpha = 0 means "no material set"
    } ke_mesh_component;

#define KE_COMPONENT_NAME_CAMERA            "camera"
#define KE_COMPONENT_NAME_DIRECTIONAL_LIGHT "directional_light"
#define KE_COMPONENT_NAME_POINT_LIGHT       "point_light"
#define KE_COMPONENT_NAME_SPOT_LIGHT        "spot_light"
#define KE_COMPONENT_NAME_MESH              "mesh"

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_COMPONENTS_H_
