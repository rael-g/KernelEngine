#ifndef KERNEL_ENGINE_RENDER_FORWARD_FORWARD_CREATE_H_
#define KERNEL_ENGINE_RENDER_FORWARD_FORWARD_CREATE_H_

#include <kernel_engine/configuration/settings.h>
#include <kernel_engine/result/result.h>
#include <stdbool.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/resource_groups.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/part/part.h>
#include <kernel_engine/schedule/schedule.h>

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

    /// Makes the transparent forward pass, whose system, in @p render_queue_set of @p render_queue, declares
    /// the pass that samples the frame's color and draws the transparent meshes over a copy of it, tested
    /// against the frame's depth, lit by the published shadow and clusters; the copy becomes the frame's color.
    /// Every argument but @p out_pass must outlive the pass.
    /// @param settings [borrowed] Read once. `ibl_enabled`, a boolean, default true: whether the pass samples the
    ///        sky for image-based light.
    /// @param out_pass [out] Receives the pass, whose destroy unregisters its systems; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a NULL pointer or a refused setting; the code of the GPU
    ///         object that could not be made, or of the schedule that refused a system.
    KE_RENDER_FORWARD_API ke_result ke_render_forward_create(
        ke_render_service *service, ke_gpu_device *device, ke_render_frame *frame, ke_render_scene_resolve *scene,
        ke_schedule *render_queue, ke_schedule_set_id render_queue_set, ke_settings *settings, ke_owner *out_pass);

#ifdef __cplusplus
}
#endif

#endif
