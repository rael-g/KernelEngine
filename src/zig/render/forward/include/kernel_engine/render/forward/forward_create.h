#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/common/types.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/logger/logger.h>
#include <kernel_engine/render/core/render_core.h>
#include <kernel_engine/render/gpu_device.h>
#include <kernel_engine/runtime/runtime.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_FORWARD_EXPORT
        #define KE_RENDER_FORWARD_API __declspec(dllexport)
    #elif defined(KE_RENDER_FORWARD_STATIC)
        #define KE_RENDER_FORWARD_API
    #else
        #define KE_RENDER_FORWARD_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_FORWARD_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    // Opaque — nothing outside this plugin calls into it; it registers its own
    // render.forward_transparent system into `runtime` at create time. Reads
    // shadow's and cluster's outputs by name through the borrowed
    // ke_render_core (same pattern as ke_render_deferred_lighting) rather than
    // a *ShadowModule/*ClusterModule pointer.
    typedef struct ke_render_forward ke_render_forward;

    typedef struct ke_render_forward_handle
    {
        ke_render_forward *ref;
        void (*destroy)(ke_render_forward *self);
    } ke_render_forward_handle;

    // Creates the transparent-forward pass (the BLEND-only counterpart to the
    // opaque G-buffer path — gbuffer_module skips BLEND materials, this pass
    // draws them, sorted back-to-front, blending into "hdr" after skybox).
    // `runtime`/`core`/`device` are borrowed. mesh_cid/transform_cid/
    // camera_cid/light_cid/ambient_cid/skybox_cid/frame_cid are cids the
    // aggregator already registered. Handle's ref is NULL on failure.
    KE_RENDER_FORWARD_API ke_render_forward_handle ke_render_forward_create(
        ke_runtime *runtime, ke_render_core *core, ke_gpu_device *device,
        ke_ndc_convention ndc, ke_logger *logger, ke_bool ibl_enabled,
        ke_component_id mesh_cid, ke_component_id transform_cid,
        ke_component_id camera_cid, ke_component_id light_cid,
        ke_component_id ambient_cid, ke_component_id skybox_cid,
        ke_component_id frame_cid, ke_error **out_error);

#ifdef __cplusplus
}
#endif
