#ifndef KERNEL_ENGINE_FRAMEWORK_CAMERA_RENDER_SYSTEM_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_CAMERA_RENDER_SYSTEM_CREATE_H_

#include <kernel_engine/kernel/framework/camera_render_system.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_camera_render_system_params
    {
        struct ke_world *world;
        ke_allocator    *allocator;
        /// Renderer NDC: Vulkan reports y_flip=1, all D3D/Vulkan use zero_to_one_depth=1,
        /// OpenGL uses both = 0. Passed in because the framework plugin doesn't link the
        /// renderer plugin — caller queries ke_render->get_ndc_convention.
        int              ndc_y_flip;
        int              ndc_zero_to_one_depth;
        /// Window aspect. C# CameraRenderSystem hard-codes 1.77 today; we mirror that
        /// while waiting for a window-size feedback channel.
        float            aspect;
    } ke_camera_render_system_params;

    KE_FRAMEWORK_API ke_result ke_camera_render_system_create(
        const ke_camera_render_system_params *params,
        ke_camera_render_system             **out_system);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_CAMERA_RENDER_SYSTEM_CREATE_H_
