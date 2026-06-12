#ifndef KERNEL_ENGINE_FRAMEWORK_LIGHT_RENDER_SYSTEM_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_LIGHT_RENDER_SYSTEM_CREATE_H_

#include <kernel_engine/kernel/framework/light_render_system.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_light_render_system_params
    {
        struct ke_world *world;
        ke_allocator    *allocator;
    } ke_light_render_system_params;

    KE_FRAMEWORK_API ke_result ke_light_render_system_create(
        const ke_light_render_system_params *params,
        ke_light_render_system             **out_system);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_LIGHT_RENDER_SYSTEM_CREATE_H_
