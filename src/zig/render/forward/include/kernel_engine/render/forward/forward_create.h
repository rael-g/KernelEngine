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
#include <kernel_engine/module/module.h>

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

    /// The values the transparent forward pass reads.
    typedef struct ke_render_forward_config
    {
        /// Whether the pass samples the sky for image-based light.
        bool ibl_enabled;
    } ke_render_forward_config;

    /// Makes the transparent forward pass. Attached, it declares in the render queue set the pass that
    /// samples the frame's color and draws the transparent meshes over a copy of it, tested against the
    /// frame's depth, lit by the published shadow and clusters; the copy becomes the frame's color.
    /// @param context [borrowed] The parts the pass is built on; read during the call.
    /// @param config [borrowed] The pass's values; Required; every field is read as given.
    /// @param out_module [out] Receives the pass; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT when the context, a part the pass uses or @p config is
    ///         NULL; the code of the GPU object that could not be made.
    KE_RENDER_FORWARD_API ke_result ke_render_forward_create(
        const ke_render_context *context, const ke_render_forward_config *config, ke_module_handle *out_module);

#ifdef __cplusplus
}
#endif

#endif
