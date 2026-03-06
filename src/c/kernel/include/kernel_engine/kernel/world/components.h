#ifndef KERNEL_ENGINE_KERNEL_WORLD_COMPONENTS_H_
#define KERNEL_ENGINE_KERNEL_WORLD_COMPONENTS_H_

#include <kernel_engine/kernel/common/math.h>
#include <kernel_engine/kernel/common/error.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // ── Built-in ECS component types ─────────────────────────────────────────

    /// @brief Spatial transform component. Every node has exactly one.
    /// @note world_matrix is recomputed each frame by the TransformSystem;
    ///       write only position, rotation, and scale.
    typedef struct ke_transform_component
    {
        ke_vec3 position;
        ke_quat rotation;
        ke_vec3 scale;
        ke_mat4 world_matrix; ///< Read-only output of the TransformSystem.
    } ke_transform_component;

    /// @brief Scene-graph hierarchy component. Every node has exactly one.
    /// All fields are entity IDs (0 = invalid / no link).
    typedef struct ke_hierarchy_component
    {
        uint64_t parent;
        uint64_t first_child;
        uint64_t next_sibling;
        uint64_t prev_sibling;
    } ke_hierarchy_component;

    /// @brief Name component. Every node has exactly one.
    typedef struct ke_name_component
    {
        char name[64];
    } ke_name_component;

    /// @brief Script component. Only scripted nodes (those with on_start/on_update
    ///        behavior) have this component.
    typedef struct ke_script_component
    {
        bool started;
        ke_result (*on_start)(uint64_t entity);
        ke_result (*on_update)(uint64_t entity, float dt);
    } ke_script_component;

    // ── Legacy struct kept for C# Transform compatibility ────────────────────

    /// @brief Spatial transform without world_matrix (position + rotation + scale only).
    typedef struct ke_transform
    {
        ke_vec3 position;
        ke_quat rotation;
        ke_vec3 scale;
    } ke_transform;

    typedef struct ke_mesh_renderer_component {
        uint32_t mesh_handle;
        uint32_t material_handle;
    } ke_mesh_renderer_component;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_WORLD_COMPONENTS_H_
