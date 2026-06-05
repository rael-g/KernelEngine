#ifndef KERNEL_ENGINE_FRAMEWORK_MESH_ASSET_SYSTEM_H_
#define KERNEL_ENGINE_FRAMEWORK_MESH_ASSET_SYSTEM_H_

// ke_mesh_asset_system — Phase 3 of the ECS-pure-nodes refactor.
//
// Reads `primitive` and `color` fields off every ke_mesh_component, bakes the
// primitive into a mesh handle via the renderer, creates a material handle for
// the color, and writes both back into the same component. Entities are
// remembered (per mesh asset system instance) so each is baked at most once
// per primitive name + color tuple — matching design decision #2: the
// primitive stays in place as the canonical name, ready for future hot-reload.
//
// Threading: this system calls ke_render::create_mesh / create_material
// directly, so it must run on the same thread as the renderer. In Lua's
// single-threaded loop that's the main thread; in C# the equivalent path
// already lives on ke.render. A future commit may swap the direct calls for a
// ResourceCommandQueue path so the system can run on ke.sim too.

#include <kernel_engine/framework/framework_export.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/world/system.h>

struct ke_world;
struct ke_render;
struct ke_mesh_render_system;

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_mesh_asset_system_params
    {
        struct ke_world             *world;
        ke_allocator                *allocator;
        struct ke_render            *render;
        struct ke_mesh_render_system *mesh_system; ///< Source of the mesh component cid.
    } ke_mesh_asset_system_params;

    typedef struct ke_mesh_asset_system ke_mesh_asset_system;

    KE_FRAMEWORK_API ke_result ke_mesh_asset_system_create(
        const ke_mesh_asset_system_params *params,
        ke_mesh_asset_system             **out_system);

    KE_FRAMEWORK_API void ke_mesh_asset_system_destroy(ke_mesh_asset_system *system);

    KE_FRAMEWORK_API void ke_mesh_asset_system_get_system_params(
        ke_mesh_asset_system *system, ke_system_params *out_params);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_MESH_ASSET_SYSTEM_H_
