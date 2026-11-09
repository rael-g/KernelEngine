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
#include <kernel_engine/runtime/runtime.h>

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

    typedef struct ke_render_cluster ke_render_cluster;

    /// [owner]
    typedef struct ke_render_cluster_handle
    {
        ke_render_cluster *ref;
        void (*destroy)(ke_render_cluster *self);
    } ke_render_cluster_handle;

    /// [bag] The values a light-cluster pass is created with, each applied as given.
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

    /** [defaults] The grid a caller gets when it sets nothing. */
    static const ke_render_cluster_config ke_render_cluster_config_defaults = {
        .grid_x = 16,
        .grid_y = 9,
        .grid_z = 24,
        .max_lights_per_cluster = 64,
    };

    /**
     * @brief Creates a light-cluster pass and registers its render-phase system.
     * @param context [borrowed] The parts the pass is built on; read during the call.
     * @param config [borrowed,optional] The pass's values; NULL selects the default of each.
     * @param out_resources [out] Receives the ids of its tag, light lists and grid; every id
     *        KE_COMPONENT_INVALID on failure.
     * @param out_cluster [out] Receives the handle; left zeroed on failure.
     * @return KE_OK, or on failure; KE_RESULT_INVALID_ARGUMENT when the context or a part of it is NULL, or a
     *         field of @p config is 0.
     */
    KE_RENDER_CLUSTER_API ke_result ke_render_cluster_create(
        const ke_render_context *context, const ke_render_cluster_config *config, ke_render_cluster_resources *out_resources,
        ke_render_cluster_handle *out_cluster);

#ifdef __cplusplus
}
#endif

#endif
