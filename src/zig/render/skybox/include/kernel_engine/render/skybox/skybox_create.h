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

    /// What the skybox pass draws over and into. The names are copied.
    typedef struct ke_render_skybox_params
    {
        ke_runtime        *runtime; ///< Registers the pass's system; borrowed, must outlive it.
        ke_render_service *service; ///< Holds the resources it reads and writes; borrowed.
        ke_gpu_device     *device;  ///< Borrowed.
        ke_render_camera  *camera;  ///< Gives the view and projection; borrowed.
        ke_component_id    camera_cid;
        ke_component_id    world_transform_cid;
        ke_component_id    skybox_cid;
        ke_component_id    frame_cid;
        /// [utf8] The HDR resource the output starts as.
        const char *input;
        /// [utf8] The depth resource whose far plane the sky fills.
        const char *depth;
        /// [utf8] The HDR resource it writes, declared the size of the backbuffer when the
        /// service has none of that name.
        const char *output;
    } ke_render_skybox_params;

    /// Registers the pass's render-phase system. A missing runtime, service, device, camera,
    /// input, depth or output fails as an invalid argument; the handle's ref is NULL on failure.
    KE_RENDER_SKYBOX_API ke_render_skybox_handle ke_render_skybox_create(
        const ke_render_skybox_params *params, ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif
