#ifndef KERNEL_ENGINE_RENDER_FRAME_FRAME_CREATE_H_
#define KERNEL_ENGINE_RENDER_FRAME_FRAME_CREATE_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/camera.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/runtime/runtime.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_FRAME_EXPORT
        #define KE_RENDER_FRAME_API __declspec(dllexport)
    #elif defined(KE_RENDER_FRAME_STATIC)
        #define KE_RENDER_FRAME_API
    #else
        #define KE_RENDER_FRAME_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_FRAME_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    /// The systems that begin and end a frame on the render service.
    typedef struct ke_render_frame
    {
        void *handle;

        /**
         * The tag the system that begins the frame writes and the system that ends it reads. A
         * pass that reads it runs inside the frame.
         */
        ke_component_id (*frame_cid)(struct ke_render_frame *self);
    } ke_render_frame;

    typedef struct ke_render_frame_handle
    {
        ke_render_frame *ref;
        void (*destroy)(ke_render_frame *self);
    } ke_render_frame_handle;

    /// What the frame needs to begin and end on the service and to publish the frame globals.
    typedef struct ke_render_frame_params
    {
        ke_runtime        *runtime; ///< Registers the frame's systems; borrowed, must outlive it.
        ke_ecs            *ecs;     ///< Registers the frame tag; borrowed.
        ke_render_service *service; ///< The frame begins and ends on it; borrowed, must outlive it.
        ke_render_camera  *camera;  ///< Turns the camera entity into matrices; borrowed, must outlive it.
        ke_component_id    camera_cid;
        ke_component_id    world_transform_cid;
        ke_component_id    directional_light_cid;
        ke_component_id    ambient_light_cid;
    } ke_render_frame_params;

    /// Registers the tag "render.frame" and the render-phase systems "render.begin_frame", which
    /// begins the frame and publishes the frame globals and the scene's light, and
    /// "render.end_frame". A missing runtime, ecs, service or camera fails as an invalid argument;
    /// the handle's ref is NULL on failure.
    KE_RENDER_FRAME_API ke_render_frame_handle ke_render_frame_create(const ke_render_frame_params *params,
                                                                      ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif
