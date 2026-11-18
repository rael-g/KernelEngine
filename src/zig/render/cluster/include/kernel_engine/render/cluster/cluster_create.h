#ifndef KERNEL_ENGINE_RENDER_CLUSTER_CLUSTER_CREATE_H_
#define KERNEL_ENGINE_RENDER_CLUSTER_CLUSTER_CREATE_H_

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

    /// The values a light-cluster pass is created with, each applied as given.
    typedef struct ke_render_cluster_config
    {
        /// Clusters across the screen.
        uint32_t grid_x;
        /// Clusters down the screen.
        uint32_t grid_y;
        /// Depth slices.
        uint32_t grid_z;
        /// Lights one cluster can list.
        uint32_t max_lights_per_cluster;
    } ke_render_cluster_config;

    /**
     * @brief Makes a light-cluster pass. Attached, it publishes the light lists and the grid in the render
     * prepare set and declares the compute pass that fills them in the render queue set.
     * @param context [borrowed] The parts the pass is built on; read during the call.
     * @param config [borrowed] The pass's values; Required; every field is read as given.
     * @param out_module [out] Receives the pass; left zeroed on failure.
     * @return KE_OK, or on failure; KE_RESULT_INVALID_ARGUMENT when the context or a part of it is NULL, or a
     *         field of @p config is 0.
     */
    KE_RENDER_CLUSTER_API ke_result ke_render_cluster_create(
        const ke_render_context *context, const ke_render_cluster_config *config, ke_module_handle *out_module);

#ifdef __cplusplus
}
#endif

#endif
