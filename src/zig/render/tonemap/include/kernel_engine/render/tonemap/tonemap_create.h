#ifndef KERNEL_ENGINE_RENDER_TONEMAP_TONEMAP_CREATE_H_
#define KERNEL_ENGINE_RENDER_TONEMAP_TONEMAP_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/assembly/part.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/scheduling/schedule.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_TONEMAP_EXPORT
        #define KE_RENDER_TONEMAP_API __declspec(dllexport)
    #elif defined(KE_RENDER_TONEMAP_STATIC)
        #define KE_RENDER_TONEMAP_API
    #else
        #define KE_RENDER_TONEMAP_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_TONEMAP_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    /// Makes the tonemap pass, whose system, in @p render_queue_set of @p render_queue, declares at
    /// KE_RENDER_STAGE_TONEMAP the pass that writes the frame's color, tonemapped, into the frame's output,
    /// which becomes the frame's color. Every argument but @p out_pass must outlive the pass.
    /// @param out_pass [out] Receives the pass, whose destroy unregisters the system; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a NULL pointer; the code of the GPU object that could not
    ///         be made, or of the schedule that refused the system.
    KE_RENDER_TONEMAP_API ke_result ke_render_tonemap_create(
        ke_render_service *service, ke_gpu_device *device, ke_render_frame *frame,
        ke_schedule *render_queue, ke_schedule_set_id render_queue_set, ke_owner *out_pass);

#ifdef __cplusplus
}
#endif

#endif
