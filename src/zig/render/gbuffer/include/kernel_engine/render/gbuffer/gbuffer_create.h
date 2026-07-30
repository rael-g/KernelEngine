#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/runtime/runtime.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_GBUFFER_EXPORT
        #define KE_RENDER_GBUFFER_API __declspec(dllexport)
    #elif defined(KE_RENDER_GBUFFER_STATIC)
        #define KE_RENDER_GBUFFER_API
    #else
        #define KE_RENDER_GBUFFER_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_GBUFFER_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    // Opaque — nothing outside this plugin calls into it; it registers its own
    // render.gbuffer system into `runtime` at create time and does its work
    // through the borrowed ke_render_service (writes gbuffer_albedo/normal/
    // emissive + depth).
    typedef struct ke_render_gbuffer ke_render_gbuffer;

    typedef struct ke_render_gbuffer_handle
    {
        ke_render_gbuffer *ref;
        void (*destroy)(ke_render_gbuffer *self);
    } ke_render_gbuffer_handle;

    // Creates the deferred G-buffer encode pass and registers it as a runtime
    // system. `runtime`/`core`/`device` are borrowed. mesh_cid/transform_cid/
    // camera_cid/frame_cid are cids the aggregator already registered (this
    // plugin never touches ke_ecs directly, only the plain ids). Handle's ref
    // is NULL on failure.
    KE_RENDER_GBUFFER_API ke_render_gbuffer_handle ke_render_gbuffer_create(
        ke_runtime *runtime, ke_render_service *core, ke_gpu_device *device,
        ke_ndc_convention ndc,
        ke_component_id mesh_cid, ke_component_id transform_cid,
        ke_component_id camera_cid, ke_component_id frame_cid,
        ke_error **out_error);

#ifdef __cplusplus
}
#endif
