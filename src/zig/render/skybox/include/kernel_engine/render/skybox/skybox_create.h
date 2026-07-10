#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/core/render_core.h>
#include <kernel_engine/render/gpu_device.h>
#include <kernel_engine/runtime/runtime.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_SKYBOX_EXPORT
        #define KE_RENDER_SKYBOX_API __declspec(dllexport)
    #elif defined(KE_RENDER_SKYBOX_STATIC)
        #define KE_RENDER_SKYBOX_API
    #else
        #define KE_RENDER_SKYBOX_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_SKYBOX_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    // Opaque — nothing outside this plugin calls into it; it registers its own
    // render.skybox system into `runtime` at create time and does its work
    // through the borrowed ke_render_core (reads "depth", writes "hdr").
    typedef struct ke_render_skybox ke_render_skybox;

    typedef struct ke_render_skybox_handle
    {
        ke_render_skybox *ref;
        void (*destroy)(ke_render_skybox *self);
    } ke_render_skybox_handle;

    // Creates the standalone skybox pass and registers it as a runtime system.
    // `runtime`/`core`/`device` are borrowed. camera_cid/transform_cid/
    // skybox_cid/frame_cid are cids the aggregator already registered (this
    // plugin never touches ke_ecs directly, only the plain ids). Handle's ref
    // is NULL on failure.
    KE_RENDER_SKYBOX_API ke_render_skybox_handle ke_render_skybox_create(
        ke_runtime *runtime, ke_render_core *core, ke_gpu_device *device,
        ke_ndc_convention ndc,
        ke_component_id camera_cid, ke_component_id transform_cid,
        ke_component_id skybox_cid, ke_component_id frame_cid,
        ke_error **out_error);

#ifdef __cplusplus
}
#endif
