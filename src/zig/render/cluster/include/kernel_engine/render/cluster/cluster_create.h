#ifndef KERNEL_ENGINE_RENDER_CLUSTER_CLUSTER_CREATE_H_
#define KERNEL_ENGINE_RENDER_CLUSTER_CLUSTER_CREATE_H_

#include <kernel_engine/settings/settings.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/render/context.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/resource_groups.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/camera.h>
#include <kernel_engine/view/view_space.h>
#include <kernel_engine/module/module.h>

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

    /**
     * @brief Makes a light-cluster pass. Attached, it publishes the light lists and the grid in the render
     * prepare set and declares the compute pass that fills them in the render queue set.
     * @param context [borrowed] The parts the pass is built on; read during the call.
     * @param settings [borrowed] Read once; each absent key takes its default, each an integer of
     *        1 or more: `grid_x` 16 and `grid_y` 9, clusters across and down the screen; `grid_z` 24,
     *        depth slices; `max_lights_per_cluster` 64, the lights one cluster can list.
     * @param out_module [out] Receives the pass; left zeroed on failure.
     * @return KE_OK, or on failure; KE_RESULT_INVALID_ARGUMENT when the context or a part of it is NULL, or a
     *         setting is refused.
     */
    KE_RENDER_CLUSTER_API ke_result ke_render_cluster_create(
        const ke_render_context *context, ke_settings *settings, ke_module_handle *out_module);

#ifdef __cplusplus
}
#endif

#endif
