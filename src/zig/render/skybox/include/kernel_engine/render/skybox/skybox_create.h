#ifndef KERNEL_ENGINE_RENDER_SKYBOX_SKYBOX_CREATE_H_
#define KERNEL_ENGINE_RENDER_SKYBOX_SKYBOX_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/camera.h>
#include <kernel_engine/assembly/part.h>
#include <kernel_engine/scheduling/schedule.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_SKYBOX_EXPORT
        #define KE_RENDER_SKYBOX_API __declspec(dllexport)
    #elif defined(KE_RENDER_SKYBOX_STATIC)
        #define KE_RENDER_SKYBOX_API
    #else
        #define KE_RENDER_SKYBOX_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_SKYBOX_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    /// Makes the skybox pass, whose system, in @p render_queue_set of @p render_queue, declares at
    /// KE_RENDER_STAGE_SKY the pass that draws the sky over the frame's color where the frame's depth is at the
    /// far plane. Every argument but @p out_pass must outlive the pass.
    /// @param out_pass [out] Receives the pass, whose destroy unregisters its systems; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a NULL pointer; the code of the GPU object that could not be
    ///         made, or of the schedule that refused a system.
    KE_RENDER_SKYBOX_API ke_result ke_render_skybox_create(
        ke_render_service *service, ke_gpu_device *device, ke_render_frame *frame, ke_render_scene_resolve *scene,
        ke_render_camera *camera, ke_schedule *render_queue, ke_schedule_set_id render_queue_set,
        ke_owner *out_pass);

#ifdef __cplusplus
}
#endif

#endif
