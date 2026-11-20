#ifndef KERNEL_ENGINE_RENDER_UI_UI_SYSTEMS_CREATE_H_
#define KERNEL_ENGINE_RENDER_UI_UI_SYSTEMS_CREATE_H_

#include <kernel_engine/part/part.h>
#include <kernel_engine/schedule/schedule.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/render/ui/ui.h>

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

    /// Registers the systems of @p ui: "render.ui.labels" in @p render_prepare_set of @p render_prepare, which lays
    /// out each label's text, and "render.ui" in @p render_queue_set of @p render_queue, which declares, at
    /// KE_RENDER_STAGE_OVERLAY, the pass drawing the quads and the labels over the frame's colour. Every argument
    /// but @p out_systems must outlive the systems.
    /// @param ui Created by this library.
    /// @param out_systems [out] Receives the systems, whose destroy unregisters them; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a NULL pointer; KE_RESULT_NOT_SUPPORTED when the systems of
    ///         @p ui are registered; the code of the schedule that refused a system.
    KE_RENDER_UI_API ke_result ke_render_ui_systems_create(
        ke_render_ui *ui, ke_schedule *render_prepare, ke_schedule_set_id render_prepare_set, ke_schedule *render_queue,
        ke_schedule_set_id render_queue_set, ke_owner *out_systems);

#ifdef __cplusplus
}
#endif

#endif
