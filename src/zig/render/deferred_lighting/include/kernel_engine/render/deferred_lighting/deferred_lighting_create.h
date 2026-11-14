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
#include <kernel_engine/module/module.h>

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

    /// The values the deferred lighting pass reads.
    typedef struct ke_render_deferred_lighting_config
    {
        /// Whether the pass samples the sky for image-based light.
        bool ibl_enabled;
    } ke_render_deferred_lighting_config;

    /// Makes the deferred lighting pass. Attached, it declares in the render queue set the pass that lights
    /// the published gbuffer over the frame's color, sampling the frame's depth, the published shadow (the
    /// neutral one when none is) and the published clusters (none added when none are).
    /// @param context [borrowed] The parts the pass is built on; read during the call.
    /// @param config [borrowed] The pass's values; Required; every field is read as given.
    /// @param out_module [out] Receives the pass; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT when the context, a part the pass uses or @p config is
    ///         NULL; the code of the GPU object that could not be made.
    KE_RENDER_DEFERRED_LIGHTING_API ke_result ke_render_deferred_lighting_create(
        const ke_render_context *context, const ke_render_deferred_lighting_config *config, ke_module_handle *out_module);

#ifdef __cplusplus
}
#endif

#endif
