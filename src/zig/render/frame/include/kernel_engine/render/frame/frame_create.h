#ifndef KERNEL_ENGINE_RENDER_FRAME_FRAME_CREATE_H_
#define KERNEL_ENGINE_RENDER_FRAME_FRAME_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/camera.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/scene_resolve.h>
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

    /// Registers the tag "render.frame" and the render-phase systems "render.begin_frame", which
    /// begins the frame and publishes the frame globals and the scene's light, and
    /// "render.end_frame". A missing runtime, ecs, service, camera or scene fails as an invalid argument;
    /// the handle's ref is NULL on failure.
    /// @param runtime Registers the frame's systems; borrowed, must outlive it.
    /// @param ecs     Registers the frame tag; borrowed.
    /// @param service The frame begins and ends on it; borrowed, must outlive it.
    /// @param camera  Turns the camera entity into matrices; borrowed, must outlive it.
    /// @param scene   Names the components the frame reads; borrowed.
    /// @param out_frame [out] Receives the handle; left zeroed on failure.
    KE_RENDER_FRAME_API ke_result ke_render_frame_create(ke_runtime *runtime, ke_ecs *ecs, ke_render_service *service,
                                                         ke_render_camera *camera, ke_render_scene_resolve *scene,
                                                         ke_render_frame_handle *out_frame);

#ifdef __cplusplus
}
#endif

#endif
