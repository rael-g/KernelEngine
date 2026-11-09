#ifndef KERNEL_ENGINE_RENDER_FORWARD_FORWARD_CREATE_H_
#define KERNEL_ENGINE_RENDER_FORWARD_FORWARD_CREATE_H_

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

    typedef struct ke_render_forward ke_render_forward;

    /// [owner]
    typedef struct ke_render_forward_handle
    {
        ke_render_forward *ref;
        void (*destroy)(ke_render_forward *self);
    } ke_render_forward_handle;

    /// [bag] The values the transparent forward pass needs. It joins the chain at KE_RENDER_STAGE_TRANSPARENT,
    /// samples the frame's color and draws over a copy of it, tested against the frame's depth.
    /// 
    typedef struct ke_render_forward_config
    {
        /// Whether the pass samples the sky for image-based light.
        bool ibl_enabled;
        /// The shadow it samples; every id KE_COMPONENT_INVALID samples the neutral one.
        ke_render_shadow_resources shadow;
        /// The clustered lights it adds; every id KE_COMPONENT_INVALID adds none.
        ke_render_cluster_resources clusters;
    } ke_render_forward_config;

    /** [defaults] The values a caller gets when it sets nothing. */
    static const ke_render_forward_config ke_render_forward_config_defaults = {
        .ibl_enabled = true,
        .shadow = { KE_COMPONENT_INVALID, KE_COMPONENT_INVALID },
        .clusters = { KE_COMPONENT_INVALID, KE_COMPONENT_INVALID, KE_COMPONENT_INVALID, KE_COMPONENT_INVALID, KE_COMPONENT_INVALID, KE_COMPONENT_INVALID, KE_COMPONENT_INVALID, KE_COMPONENT_INVALID },
    };

    /// Registers the pass's render-phase system. A missing runtime, service or device fails
    /// as an invalid argument.
    /// @param context [borrowed] The parts the pass is built on; read during the call.
    /// @param config [borrowed,optional] The pass\'s values; NULL selects the defaults.
    /// @param out_forward [out] Receives the handle; left zeroed on failure.
    KE_RENDER_FORWARD_API ke_result ke_render_forward_create(
        const ke_render_context *context, const ke_render_forward_config *config, ke_render_forward_handle *out_forward);

#ifdef __cplusplus
}
#endif

#endif
