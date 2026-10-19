#ifndef KERNEL_ENGINE_RENDER_CLUSTER_CLUSTER_CREATE_H_
#define KERNEL_ENGINE_RENDER_CLUSTER_CLUSTER_CREATE_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/logger/logger.h>
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

    typedef struct ke_render_cluster_handle
    {
        ke_render_cluster *ref;
        void (*destroy)(ke_render_cluster *self);
    } ke_render_cluster_handle;

    /// What the light-cluster pass culls and publishes. The name is copied.
    typedef struct ke_render_cluster_params
    {
        ke_runtime        *runtime;    ///< Registers the pass's system; borrowed, must outlive it.
        ke_render_service *service;    ///< Receives the published buffers; borrowed.
        ke_gpu_device     *device;     ///< Borrowed.
        ke_logger         *logger;     ///< Optional, borrowed.
        ke_view_space     *view_space; ///< Builds the cluster frusta; borrowed.
        ke_render_camera  *camera;     ///< Gives the camera's projection; borrowed.
        ke_component_id    point_light_cid;
        ke_component_id    spot_light_cid;
        ke_component_id    world_transform_cid;
        ke_component_id    camera_cid;
        ke_component_id    frame_cid;
        /// [utf8] The cluster group it writes: a tag under the group's own name, and the light
        /// lists and grid under the suffixes of kernel_engine/render/resource_groups.h.
        const char *output;
        /// Clusters across the screen. 0 takes the default.
        uint32_t grid_x;
        /// Clusters down the screen. 0 takes the default.
        uint32_t grid_y;
        /// Depth slices. 0 takes the default.
        uint32_t grid_z;
        /// Lights one cluster can list. 0 takes the default.
        uint32_t max_lights_per_cluster;
    } ke_render_cluster_params;

    /// Registers the pass's render-phase system. A missing runtime, service, device, view space,
    /// camera or output fails as an invalid argument; the handle's ref is NULL on failure.
    KE_RENDER_CLUSTER_API ke_render_cluster_handle ke_render_cluster_create(
        const ke_render_cluster_params *params, ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif
