#ifndef KERNEL_ENGINE_FRAMEWORK_MESH_RENDER_SYSTEM_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_MESH_RENDER_SYSTEM_CREATE_H_

#include <kernel_engine/kernel/framework/mesh_render_system.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_mesh_render_system_params
    {
        struct ke_world *world;
        ke_allocator    *allocator;
    } ke_mesh_render_system_params;

    KE_FRAMEWORK_API ke_result ke_mesh_render_system_create(
        const ke_mesh_render_system_params *params,
        ke_mesh_render_system             **out_system);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_MESH_RENDER_SYSTEM_CREATE_H_
