#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/logger/logger.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
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

    KE_RENDER_CLUSTER_API ke_render_cluster_handle ke_render_cluster_create(
        ke_runtime *runtime, ke_render_service *core, ke_gpu_device *device,
        ke_logger *logger, uint32_t grid_x, uint32_t grid_y, uint32_t grid_z,
        uint32_t max_lights_per_cluster,
        ke_component_id point_light_cid, ke_component_id spot_light_cid,
        ke_component_id world_transform_cid, ke_component_id camera_cid,
        ke_component_id frame_cid, ke_error **out_error);

#ifdef __cplusplus
}
#endif
