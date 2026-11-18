#ifndef KERNEL_ENGINE_RENDER_FRAME_FRAME_CREATE_H_
#define KERNEL_ENGINE_RENDER_FRAME_FRAME_CREATE_H_

#include <kernel_engine/settings/settings.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/render/camera.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/math/math.h>
#include <kernel_engine/render_graph/render_graph.h>

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


    /// Makes the frame and registers the tag "render.frame" in @p ecs. Its systems come from
    /// ke_render_frame_systems_create.
    /// @param ecs     The render world; registers the frame tag; borrowed.
    /// @param graph   The frame is declared into it; borrowed, must outlive it.
    /// @param service The frame begins, uploads and presents on it; borrowed, must outlive it.
    /// @param camera  Turns the camera entity into matrices; borrowed, must outlive it.
    /// @param scene   Names the components the frame reads; borrowed, must outlive it.
    /// @param color_format Format of the colour the frame begins with, up to KE_RENDER_STAGE_HDR_POST.
    /// @param depth_format Format of the frame's depth.
    /// @param settings [borrowed] Read once. `clear_color`, four numbers from 0 to 1 under
    ///        `clear_color.0` to `clear_color.3`, default 0, 0, 0, 1: the colour the frame's colour is
    ///        cleared to.
    /// @param out_frame [out] Receives the handle; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a NULL part or settings, an invalid format, or a
    ///         setting that is unknown, of another type or out of its range;
    ///         the ecs's code when it refuses the tag; KE_RESULT_OUT_OF_MEMORY.
    KE_RENDER_FRAME_API ke_result ke_render_frame_create(ke_ecs *ecs, ke_render_graph *graph, ke_render_service *service,
                                                         ke_render_camera *camera, ke_render_scene_resolve *scene,
                                                         ke_gpu_texture_format color_format, ke_gpu_texture_format depth_format,
                                                         ke_settings *settings, ke_render_frame_handle *out_frame);

#ifdef __cplusplus
}
#endif

#endif
