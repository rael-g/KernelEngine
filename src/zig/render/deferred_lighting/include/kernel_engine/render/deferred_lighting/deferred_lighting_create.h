#ifndef KERNEL_ENGINE_RENDER_DEFERRED_LIGHTING_DEFERRED_LIGHTING_CREATE_H_
#define KERNEL_ENGINE_RENDER_DEFERRED_LIGHTING_DEFERRED_LIGHTING_CREATE_H_

#include <kernel_engine/result/result.h>
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

    /// What the deferred lighting pass reads. It joins the chain at KE_RENDER_STAGE_OPAQUE and draws
    /// [bag] over the frame's color, sampling the frame's depth.
    typedef struct ke_render_deferred_lighting_params
    {
        ke_runtime        *runtime; ///< Registers the pass's system; borrowed, must outlive it.
        ke_render_service *service; ///< Holds the resources it reads and writes; borrowed.
        ke_gpu_device     *device;  ///< Borrowed.
        bool               ibl_enabled;
        ke_render_scene_resolve *scene; ///< Names the components the pass reads; borrowed.
        ke_render_frame   *frame;  ///< The pass runs inside its frame; borrowed.
        /// The gbuffer it lights.
        ke_render_gbuffer_resources gbuffer;
        /// The shadow it samples; every id KE_COMPONENT_INVALID samples the neutral one.
        ke_render_shadow_resources shadow;
        /// The clustered lights it adds; every id KE_COMPONENT_INVALID adds none.
        ke_render_cluster_resources clusters;
    } ke_render_deferred_lighting_params;

    /// Registers the pass's render-phase system. A missing runtime, service or device, or a
    /// gbuffer with an invalid id, fails as an invalid argument.
    /// @param out_lighting [out] Receives the handle; left zeroed on failure.
    KE_RENDER_DEFERRED_LIGHTING_API ke_result ke_render_deferred_lighting_create(
        const ke_render_deferred_lighting_params *params, ke_render_deferred_lighting_handle *out_lighting);

#ifdef __cplusplus
}
#endif

#endif
