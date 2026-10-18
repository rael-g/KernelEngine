#ifndef KERNEL_ENGINE_RENDER_FORWARD_FORWARD_CREATE_H_
#define KERNEL_ENGINE_RENDER_FORWARD_FORWARD_CREATE_H_

#include <kernel_engine/common/error.h>
#include <stdbool.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/logger/logger.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/runtime/runtime.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_FORWARD_EXPORT
        #define KE_RENDER_FORWARD_API __declspec(dllexport)
    #elif defined(KE_RENDER_FORWARD_STATIC)
        #define KE_RENDER_FORWARD_API
    #else
        #define KE_RENDER_FORWARD_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_FORWARD_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_render_forward ke_render_forward;

    typedef struct ke_render_forward_handle
    {
        ke_render_forward *ref;
        void (*destroy)(ke_render_forward *self);
    } ke_render_forward_handle;

    /// What the transparent forward pass needs. It joins the chain at KE_RENDER_STAGE_TRANSPARENT,
    /// samples the frame's color and draws over a copy of it, tested against the frame's depth.
    /// The group names are copied.
    typedef struct ke_render_forward_params
    {
        ke_runtime        *runtime; ///< Registers the pass's system; borrowed, must outlive it.
        ke_render_service *service; ///< Holds the frame's color and the groups; borrowed.
        ke_gpu_device     *device;  ///< Borrowed.
        ke_logger         *logger;  ///< Optional, borrowed.
        bool               ibl_enabled;
        ke_component_id    mesh_cid;
        ke_component_id    world_transform_cid;
        ke_component_id    camera_cid;
        ke_component_id    skybox_cid;
        ke_component_id    frame_cid;
        /// [utf8] Optional shadow group; without one the shadow is the neutral one.
        const char *shadow;
        /// [utf8] Optional cluster group; without one no clustered light is bound.
        const char *clusters;
    } ke_render_forward_params;

    /// Registers the pass's render-phase system. A missing runtime, service or device fails
    /// as an invalid argument; the handle's ref is NULL on failure.
    KE_RENDER_FORWARD_API ke_render_forward_handle ke_render_forward_create(
        const ke_render_forward_params *params, ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif
