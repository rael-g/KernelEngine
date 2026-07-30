#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/common/types.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/runtime/runtime.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_SHADOW_EXPORT
        #define KE_RENDER_SHADOW_API __declspec(dllexport)
    #elif defined(KE_RENDER_SHADOW_STATIC)
        #define KE_RENDER_SHADOW_API
    #else
        #define KE_RENDER_SHADOW_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_SHADOW_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    // Opaque — nothing outside this plugin calls into it; it registers its own
    // render.shadow system into `runtime` at create time (only when `enabled`)
    // and publishes its outputs through the borrowed ke_render_service's named-
    // resource table ("shadow_map" view, "shadow_lvp" buffer) rather than a
    // vtable another pass would call into.
    typedef struct ke_render_shadow ke_render_shadow;

    typedef struct ke_render_shadow_handle
    {
        ke_render_shadow *ref;
        void (*destroy)(ke_render_shadow *self);
    } ke_render_shadow_handle;

    // Creates the shadow-depth pass. `runtime`/`core`/`device` are borrowed.
    // mesh_cid/transform_cid/light_cid/frame_cid are cids the aggregator
    // already registered. When `enabled` is false, the tiny "shadow_lvp"
    // uniform is still published (shadow_feature.slang's neutral-default hook
    // resource) but no render target/pipeline/system is created — deferred/
    // forward's setup resolves shadow_map's absence as the "off" signal.
    // Handle's ref is NULL on failure.
    KE_RENDER_SHADOW_API ke_render_shadow_handle ke_render_shadow_create(
        ke_runtime *runtime, ke_render_service *core, ke_gpu_device *device,
        ke_ndc_convention ndc, ke_bool enabled,
        ke_component_id mesh_cid, ke_component_id transform_cid,
        ke_component_id light_cid, ke_component_id frame_cid,
        ke_error **out_error);

#ifdef __cplusplus
}
#endif
