#ifndef KERNEL_ENGINE_RENDER_CLUSTER_CLUSTER_CREATE_H_
#define KERNEL_ENGINE_RENDER_CLUSTER_CLUSTER_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/frame.h>
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
        /// [default:16] Clusters across the screen.
        uint32_t grid_x;
        /// [default:9] Clusters down the screen.
        uint32_t grid_y;
        /// [default:24] Depth slices.
        uint32_t grid_z;
        /// [default:64] Lights one cluster can list.
        uint32_t max_lights_per_cluster;
    } ke_render_cluster_config;

    /**
     * @brief Creates a light-cluster pass and registers its render-phase system.
     * @param runtime Registers the pass's system; borrowed, must outlive it.
     * @param service Receives the published buffers; borrowed.
     * @param device Borrowed.
     * @param view_space Builds the cluster frusta; borrowed.
     * @param camera Borrowed.
     * @param scene Names the components the pass reads; borrowed.
     * @param frame The pass runs inside its frame; borrowed.
     * @param output [utf8] The cluster group it writes, copied: a tag under the group's own name,
     *        and the light lists and grid under the suffixes of kernel_engine/render/resource_groups.h.
     * @param config [borrowed,optional] The pass's values; NULL selects the default of each.
     * @param out_cluster [out] Receives the handle; left zeroed on failure.
     * @return KE_OK, or on failure; KE_RESULT_INVALID_ARGUMENT when a dependency or @p output is
     *         NULL, or a field of @p config is 0.
     */
    KE_RENDER_CLUSTER_API ke_result ke_render_cluster_create(
        ke_runtime *runtime, ke_render_service *service, ke_gpu_device *device, ke_view_space *view_space,
        ke_render_camera *camera, ke_render_scene_resolve *scene, ke_render_frame *frame, const char *output,
        const ke_render_cluster_config *config, ke_render_cluster_handle *out_cluster);

#ifdef __cplusplus
}
#endif

#endif
