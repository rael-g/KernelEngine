#ifndef KERNEL_ENGINE_RENDER_UI_UI_CREATE_H_
#define KERNEL_ENGINE_RENDER_UI_UI_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/handles.h>
#include <kernel_engine/render/ui/components.h>
#include <kernel_engine/render/ui/ui.h>
#include <kernel_engine/runtime/runtime.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_UI_EXPORT
        #define KE_RENDER_UI_API __declspec(dllexport)
    #elif defined(KE_RENDER_UI_STATIC)
        #define KE_RENDER_UI_API
    #else
        #define KE_RENDER_UI_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_UI_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    /// [bag] What the ui pass needs to draw its quads and labels over the frame's color.
    typedef struct ke_render_ui_params
    {
        ke_runtime        *runtime; ///< Registers the pass's systems; borrowed, must outlive it.
        ke_ecs            *ecs;     ///< Registers the quad and label components; borrowed.
        /// Holds the frame's color, over which the pass draws at KE_RENDER_STAGE_OVERLAY; borrowed.
        ke_render_service *service;
        ke_gpu_device     *device;  ///< Borrowed.
        ke_render_frame   *frame;  ///< The pass runs inside its frame; borrowed.
    } ke_render_ui_params;

    /// Registers the pass's update-phase label system and render-phase system. A missing
    /// runtime, ecs, service or device fails as an invalid argument.
    /// @param out_ui [out] Receives the handle; left zeroed on failure.
    KE_RENDER_UI_API ke_result ke_render_ui_create(const ke_render_ui_params *params,
                                                   ke_render_ui_handle *out_ui);

#ifdef __cplusplus
}
#endif

#endif
