#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/common/types.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/logger/logger.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/runtime/runtime.h>

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

    // Opaque — nothing outside this plugin calls into it; it registers its own
    // render.deferred_lighting system into `runtime` at create time. Reads
    // shadow's and cluster's outputs by name through the borrowed
    // ke_render_service's named-resource table ("shadow_map" view, "shadow_lvp"
    // buffer, "cluster_lights" bind group) rather than a *ShadowModule/
    // *ClusterModule pointer.
    typedef struct ke_render_deferred_lighting ke_render_deferred_lighting;

    typedef struct ke_render_deferred_lighting_handle
    {
        ke_render_deferred_lighting *ref;
        void (*destroy)(ke_render_deferred_lighting *self);
    } ke_render_deferred_lighting_handle;

    // Creates the deferred-lighting pass (the opaque path's second half —
    // decodes the G-buffer and shades it). `runtime`/`core`/`device` are
    // borrowed. camera_cid/transform_cid/light_cid/ambient_cid/skybox_cid/
    // frame_cid are cids the aggregator already registered. Handle's ref is
    // NULL on failure.
    KE_RENDER_DEFERRED_LIGHTING_API ke_render_deferred_lighting_handle ke_render_deferred_lighting_create(
        ke_runtime *runtime, ke_render_service *core, ke_gpu_device *device,
        ke_ndc_convention ndc, ke_logger *logger, ke_bool ibl_enabled,
        ke_component_id camera_cid, ke_component_id transform_cid,
        ke_component_id light_cid, ke_component_id ambient_cid,
        ke_component_id skybox_cid, ke_component_id frame_cid,
        ke_error **out_error);

#ifdef __cplusplus
}
#endif
