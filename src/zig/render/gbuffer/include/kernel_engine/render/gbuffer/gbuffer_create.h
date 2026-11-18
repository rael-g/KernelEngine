#ifndef KERNEL_ENGINE_RENDER_GBUFFER_GBUFFER_CREATE_H_
#define KERNEL_ENGINE_RENDER_GBUFFER_GBUFFER_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/render/context.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/resource_groups.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/module/module.h>

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

    /// Makes the gbuffer pass. Attached, it publishes the albedo, normal and emissive targets, each the
    /// size of the frame's output, in the render prepare set, and declares the pass that draws the opaque
    /// meshes and sprites into them and the frame's depth in the render queue set.
    /// @param context [borrowed] The parts the pass is built on; read during the call.
    /// @param out_module [out] Receives the pass; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT when the context or a part the pass uses is NULL; the
    ///         code of the GPU object that could not be made.
    KE_RENDER_GBUFFER_API ke_result ke_render_gbuffer_create(
        const ke_render_context *context, ke_module_handle *out_module);

#ifdef __cplusplus
}
#endif

#endif
