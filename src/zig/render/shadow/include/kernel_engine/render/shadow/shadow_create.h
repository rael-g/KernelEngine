#ifndef KERNEL_ENGINE_RENDER_SHADOW_SHADOW_CREATE_H_
#define KERNEL_ENGINE_RENDER_SHADOW_SHADOW_CREATE_H_

#include <kernel_engine/configuration/settings.h>
#include <kernel_engine/result/result.h>
#include <stdbool.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/resource_groups.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/view/view_space.h>
#include <kernel_engine/assembly/part.h>
#include <kernel_engine/schedule/schedule.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_SHADOW_EXPORT
        #define KE_RENDER_SHADOW_API __declspec(dllexport)
    #elif defined(KE_RENDER_SHADOW_STATIC)
        #define KE_RENDER_SHADOW_API
    #else
        #define KE_RENDER_SHADOW_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_SHADOW_API __attribute__((visibility("default")))
#endif

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// Makes the directional shadow pass, which publishes the shadow map and the light's view-projection in
    /// @p render_prepare_set of @p render_prepare, and declares the pass that draws the casters into the map in
    /// @p render_queue_set of @p render_queue. Every argument but @p out_pass must outlive the pass.
    /// @param settings [borrowed] Read once; each absent key takes its default. `resolution`, an integer, 1024:
    ///        edge of the square map in texels. `light_distance`, 25: how far back along the light the shadow
    ///        camera sits. `extent`, 20: width and height of the shadowed area in world units; a scene larger than
    ///        it loses shadows outside it. `near_plane`, 0.1, and `far_plane`, 50: the shadow camera's planes.
    /// @param out_pass [out] Receives the pass, whose destroy unregisters its systems; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a NULL pointer, a setting that is unknown, of another type or
    ///         out of its range, or a near plane not before the far one; the code of the GPU object that could not
    ///         be made, or of the schedule that refused a system.
    KE_RENDER_SHADOW_API ke_result ke_render_shadow_create(
        ke_render_service *service, ke_gpu_device *device, ke_render_frame *frame, ke_render_scene_resolve *scene,
        ke_view_space *view_space, ke_schedule *render_prepare, ke_schedule_set_id render_prepare_set,
        ke_schedule *render_queue, ke_schedule_set_id render_queue_set, ke_settings *settings, ke_owner *out_pass);

#ifdef __cplusplus
}
#endif

#endif
