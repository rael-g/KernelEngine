#ifndef KERNEL_ENGINE_RENDER_DEFERRED_LIGHTING_DEFERRED_LIGHTING_CREATE_H_
#define KERNEL_ENGINE_RENDER_DEFERRED_LIGHTING_DEFERRED_LIGHTING_CREATE_H_

#include <kernel_engine/configuration/settings.h>
#include <kernel_engine/result/result.h>
#include <stdbool.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/resource_groups.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/assembly/part.h>
#include <kernel_engine/scheduling/schedule.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_DEFERRED_LIGHTING_EXPORT
        #define KE_RENDER_DEFERRED_LIGHTING_API __declspec(dllexport)
    #elif defined(KE_RENDER_DEFERRED_LIGHTING_STATIC)
        #define KE_RENDER_DEFERRED_LIGHTING_API
    #else
        #define KE_RENDER_DEFERRED_LIGHTING_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_DEFERRED_LIGHTING_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    /// Makes the deferred lighting pass, whose system, in @p render_queue_set of @p render_queue, declares the
    /// pass that lights the published gbuffer over the frame's color, sampling the frame's depth, the published
    /// shadow (the neutral one when none is) and the published clusters (none added when none are). Every
    /// argument but @p out_pass must outlive the pass.
    /// @param settings [borrowed] Read once. `ibl_enabled`, a boolean, default true: whether the pass samples the
    ///        sky for image-based light.
    /// @param out_pass [out] Receives the pass, whose destroy unregisters its systems; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a NULL pointer or a refused setting; the code of the GPU
    ///         object that could not be made, or of the schedule that refused a system.
    KE_RENDER_DEFERRED_LIGHTING_API ke_result ke_render_deferred_lighting_create(
        ke_render_service *service, ke_gpu_device *device, ke_render_frame *frame, ke_render_scene_resolve *scene,
        ke_schedule *render_queue, ke_schedule_set_id render_queue_set, ke_settings *settings, ke_owner *out_pass);

#ifdef __cplusplus
}
#endif

#endif
