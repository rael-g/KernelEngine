#ifndef KERNEL_ENGINE_RENDER_DEFERRED_LIGHTING_DEFERRED_LIGHTING_CREATE_H_
#define KERNEL_ENGINE_RENDER_DEFERRED_LIGHTING_DEFERRED_LIGHTING_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/render/context.h>
#include <stdbool.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/resource_groups.h>
#include <kernel_engine/render/scene_resolve.h>
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

    typedef struct ke_render_deferred_lighting ke_render_deferred_lighting;

    /// [owner]
    typedef struct ke_render_deferred_lighting_handle
    {
        ke_render_deferred_lighting *ref;
        void (*destroy)(ke_render_deferred_lighting *self);
    } ke_render_deferred_lighting_handle;

    /// [bag] The values the deferred lighting pass reads. It joins the chain at KE_RENDER_STAGE_OPAQUE and draws
    /// over the frame's color, sampling the frame's depth.
    typedef struct ke_render_deferred_lighting_config
    {
        /// Whether the pass samples the sky for image-based light.
        bool ibl_enabled;
        /// The gbuffer it lights.
        ke_render_gbuffer_resources gbuffer;
        /// The shadow it samples; every id KE_COMPONENT_INVALID samples the neutral one.
        ke_render_shadow_resources shadow;
        /// The clustered lights it adds; every id KE_COMPONENT_INVALID adds none.
        ke_render_cluster_resources clusters;
    } ke_render_deferred_lighting_config;

    /** [defaults] The values a caller gets when it sets nothing. */
    static const ke_render_deferred_lighting_config ke_render_deferred_lighting_config_defaults = {
        .ibl_enabled = true,
        .gbuffer = { KE_COMPONENT_INVALID, KE_COMPONENT_INVALID, KE_COMPONENT_INVALID },
        .shadow = { KE_COMPONENT_INVALID, KE_COMPONENT_INVALID },
        .clusters = { KE_COMPONENT_INVALID, KE_COMPONENT_INVALID, KE_COMPONENT_INVALID, KE_COMPONENT_INVALID, KE_COMPONENT_INVALID, KE_COMPONENT_INVALID, KE_COMPONENT_INVALID, KE_COMPONENT_INVALID },
    };

    /// Registers the pass's render-phase system. A missing runtime, service or device, or a
    /// gbuffer with an invalid id, fails as an invalid argument.
    /// @param context [borrowed] The parts the pass is built on; read during the call.
    /// @param config [borrowed,optional] The pass\'s values; NULL selects the defaults.
    /// @param out_lighting [out] Receives the handle; left zeroed on failure.
    KE_RENDER_DEFERRED_LIGHTING_API ke_result ke_render_deferred_lighting_create(
        const ke_render_context *context, const ke_render_deferred_lighting_config *config, ke_render_deferred_lighting_handle *out_lighting);

#ifdef __cplusplus
}
#endif

#endif
