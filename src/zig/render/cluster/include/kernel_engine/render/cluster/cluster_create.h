#ifndef KERNEL_ENGINE_RENDER_CLUSTER_CLUSTER_CREATE_H_
#define KERNEL_ENGINE_RENDER_CLUSTER_CLUSTER_CREATE_H_

#include <kernel_engine/configuration/settings.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/resource_groups.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/camera.h>
#include <kernel_engine/view/view_space.h>
#include <kernel_engine/assembly/part.h>
#include <kernel_engine/schedule/schedule.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_CLUSTER_EXPORT
        #define KE_RENDER_CLUSTER_API __declspec(dllexport)
    #elif defined(KE_RENDER_CLUSTER_STATIC)
        #define KE_RENDER_CLUSTER_API
    #else
        #define KE_RENDER_CLUSTER_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_CLUSTER_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    /// Makes a light-cluster pass, which publishes the light lists and the grid in @p render_prepare_set of
    /// @p render_prepare and declares the compute pass that fills them in @p render_queue_set of @p render_queue.
    /// Every argument but @p out_pass must outlive the pass.
    /// @param settings [borrowed] Read once; each absent key takes its default, each an integer of 1 or more:
    ///        `grid_x` 16 and `grid_y` 9, clusters across and down the screen; `grid_z` 24, depth slices;
    ///        `max_lights_per_cluster` 64, the lights one cluster can list.
    /// @param out_pass [out] Receives the pass, whose destroy unregisters its systems; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a NULL pointer or a refused setting; the code of the schedule
    ///         that refused a system.
    KE_RENDER_CLUSTER_API ke_result ke_render_cluster_create(
        ke_render_service *service, ke_gpu_device *device, ke_render_frame *frame, ke_render_scene_resolve *scene,
        ke_render_camera *camera, ke_view_space *view_space, ke_schedule *render_prepare,
        ke_schedule_set_id render_prepare_set, ke_schedule *render_queue, ke_schedule_set_id render_queue_set,
        ke_settings *settings, ke_owner *out_pass);

#ifdef __cplusplus
}
#endif

#endif
