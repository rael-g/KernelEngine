#ifndef KERNEL_ENGINE_RENDER_FRAME_FRAME_SYSTEMS_CREATE_H_
#define KERNEL_ENGINE_RENDER_FRAME_FRAME_SYSTEMS_CREATE_H_

#include <kernel_engine/assembly/part.h>
#include <kernel_engine/schedule/schedule.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/render/frame.h>

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

    /// Registers the systems of @p frame: "render.begin_frame" in @p render_begin_set of @p render_begin, which
    /// begins the frame, publishes the frame globals and the scene's light and declares the clear of the frame's
    /// colour and depth, and "render.end_frame" in @p render_submit_set of @p render_submit, which copies the
    /// colour into the output when no pass claimed it, submits the uploads, executes the graph and presents. A
    /// frame the render target has nothing to draw into is neither declared nor executed. Every argument but
    /// @p out_systems must outlive the systems.
    /// @param frame Created by this library.
    /// @param out_systems [out] Receives the systems, whose destroy unregisters them; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a NULL pointer; KE_RESULT_NOT_SUPPORTED when the systems of
    ///         @p frame are registered; the code of the schedule that refused a system.
    KE_RENDER_FRAME_API ke_result ke_render_frame_systems_create(
        ke_render_frame *frame, ke_schedule *render_begin, ke_schedule_set_id render_begin_set,
        ke_schedule *render_submit, ke_schedule_set_id render_submit_set, ke_owner *out_systems);

#ifdef __cplusplus
}
#endif

#endif
