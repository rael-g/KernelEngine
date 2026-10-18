#ifndef KERNEL_ENGINE_RENDER_SKYBOX_SKYBOX_CREATE_H_
#define KERNEL_ENGINE_RENDER_SKYBOX_SKYBOX_CREATE_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/camera.h>
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

    /// What the skybox pass needs. It joins the chain at KE_RENDER_STAGE_SKY and draws over the
    /// frame's color where the frame's depth is at the far plane.
    typedef struct ke_render_skybox_params
    {
        ke_runtime        *runtime; ///< Registers the pass's system; borrowed, must outlive it.
        ke_render_service *service; ///< Holds the frame's color and depth; borrowed.
        ke_gpu_device     *device;  ///< Borrowed.
        ke_render_camera  *camera;  ///< Gives the view and projection; borrowed.
        ke_component_id    camera_cid;
        ke_component_id    world_transform_cid;
        ke_component_id    skybox_cid;
        ke_component_id    frame_cid;
    } ke_render_skybox_params;

    /// Registers the pass's render-phase system. A missing runtime, service, device or camera
    /// fails as an invalid argument; the handle's ref is NULL on failure.
    KE_RENDER_SKYBOX_API ke_render_skybox_handle ke_render_skybox_create(
        const ke_render_skybox_params *params, ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif
