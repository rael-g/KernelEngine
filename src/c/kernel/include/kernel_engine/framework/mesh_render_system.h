#ifndef KERNEL_ENGINE_FRAMEWORK_MESH_RENDER_SYSTEM_H_
#define KERNEL_ENGINE_FRAMEWORK_MESH_RENDER_SYSTEM_H_

// ke_mesh_render_system — native port of C# MeshRenderSystem.
//
// Owns the MeshComponent cid. On every tick it iterates the contiguous mesh
// query, skips entries with an invalid MeshHandle, fetches the entity's
// TransformComponent.world_matrix and appends one ke_draw_command per visible
// mesh into ke_frame_packet.draw_commands (until capacity).

#include <kernel_engine/framework/framework_export.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/common/handles.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/system.h>

struct ke_world;

#ifdef __cplusplus
extern "C"
{
#endif

    /// Layout MUST mirror KernelEngine.Framework.MeshComponent (two sequential
    /// handle wrappers, each carrying a single uint).
    typedef struct ke_mesh_component
    {
        ke_mesh_handle     mesh;
        ke_material_handle material;
    } ke_mesh_component;

    typedef struct ke_mesh_render_system_params
    {
        struct ke_world *world;
        ke_allocator    *allocator;
    } ke_mesh_render_system_params;

    typedef struct ke_mesh_render_system ke_mesh_render_system;

    KE_FRAMEWORK_API ke_result ke_mesh_render_system_create(
        const ke_mesh_render_system_params *params,
        ke_mesh_render_system             **out_system);

    KE_FRAMEWORK_API void ke_mesh_render_system_destroy(ke_mesh_render_system *system);

    KE_FRAMEWORK_API ke_component_id ke_mesh_render_system_component_id(
        const ke_mesh_render_system *system);

    KE_FRAMEWORK_API void ke_mesh_render_system_get_system_params(
        ke_mesh_render_system *system, ke_system_params *out_params);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_MESH_RENDER_SYSTEM_H_
