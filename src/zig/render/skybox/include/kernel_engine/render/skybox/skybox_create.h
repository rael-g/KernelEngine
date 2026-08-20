#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/view/view_space.h>
#include <kernel_engine/runtime/runtime.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_SKYBOX_EXPORT
        #define KE_RENDER_SKYBOX_API __declspec(dllexport)
    #elif defined(KE_RENDER_SKYBOX_STATIC)
        #define KE_RENDER_SKYBOX_API
    #else
        #define KE_RENDER_SKYBOX_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_SKYBOX_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_render_skybox ke_render_skybox;

    typedef struct ke_render_skybox_handle
    {
        ke_render_skybox *ref;
        void (*destroy)(ke_render_skybox *self);
    } ke_render_skybox_handle;

    KE_RENDER_SKYBOX_API ke_render_skybox_handle ke_render_skybox_create(
        ke_runtime *runtime, ke_render_service *core, ke_gpu_device *device,
        ke_ndc_convention ndc, ke_view_space *view_space,
        ke_component_id camera_cid, ke_component_id world_transform_cid,
        ke_component_id skybox_cid, ke_component_id frame_cid,
        ke_error **out_error);

#ifdef __cplusplus
}
#endif
