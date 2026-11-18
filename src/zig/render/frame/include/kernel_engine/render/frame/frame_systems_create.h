#ifndef KERNEL_ENGINE_RENDER_FRAME_FRAME_SYSTEMS_CREATE_H_
#define KERNEL_ENGINE_RENDER_FRAME_FRAME_SYSTEMS_CREATE_H_

#include <kernel_engine/module/module.h>
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

    /// Creates the module of @p frame: attaching it registers, in the render schedule, "render.begin_frame"
    /// in the render begin set, which begins the frame, publishes the frame globals and the scene's light
    /// and declares the clear of the frame's colour and depth, and "render.end_frame" in the render
    /// submit set, which copies the colour into the output when no pass claimed it, submits the uploads, executes the graph and
    /// presents. A frame the render target has nothing to draw into is neither declared nor executed.
    /// @param frame [borrowed] Created by this library; must outlive the module.
    /// @param out_module [out] Receives the module; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; KE_RESULT_OUT_OF_MEMORY.
    KE_RENDER_FRAME_API ke_result ke_render_frame_systems_create(ke_render_frame *frame, ke_module_handle *out_module);

#ifdef __cplusplus
}
#endif

#endif
