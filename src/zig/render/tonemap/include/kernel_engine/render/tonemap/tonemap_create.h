#ifndef KERNEL_ENGINE_RENDER_TONEMAP_TONEMAP_CREATE_H_
#define KERNEL_ENGINE_RENDER_TONEMAP_TONEMAP_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/render/context.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/module/module.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_TONEMAP_EXPORT
        #define KE_RENDER_TONEMAP_API __declspec(dllexport)
    #elif defined(KE_RENDER_TONEMAP_STATIC)
        #define KE_RENDER_TONEMAP_API
    #else
        #define KE_RENDER_TONEMAP_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_TONEMAP_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    /// Makes the tonemap pass. Attached, it declares in the render queue set, at KE_RENDER_STAGE_TONEMAP,
    /// the pass that writes the frame's color, tonemapped, into the frame's output, which becomes the
    /// frame's color.
    /// @param context [borrowed] The parts the pass is built on; read during the call.
    /// @param out_module [out] Receives the pass; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT when the context or a part the pass uses is NULL; the
    ///         code of the GPU object that could not be made.
    KE_RENDER_TONEMAP_API ke_result ke_render_tonemap_create(
        const ke_render_context *context, ke_module_handle *out_module);

#ifdef __cplusplus
}
#endif

#endif
