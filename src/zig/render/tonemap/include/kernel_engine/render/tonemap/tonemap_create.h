#ifndef KERNEL_ENGINE_RENDER_TONEMAP_TONEMAP_CREATE_H_
#define KERNEL_ENGINE_RENDER_TONEMAP_TONEMAP_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/render/context.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/runtime/runtime.h>

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

    typedef struct ke_render_tonemap ke_render_tonemap;

    /// [owner]
    typedef struct ke_render_tonemap_handle
    {
        ke_render_tonemap *ref;
        void (*destroy)(ke_render_tonemap *self);
    } ke_render_tonemap_handle;

    /// Registers the pass's render-phase system. A missing runtime, service or device fails as an
    /// invalid argument.
    /// It joins the service's chain at KE_RENDER_STAGE_TONEMAP and replaces the frame's color with
    /// its tonemapped copy.
    /// @param context [borrowed] The parts the pass is built on; read during the call.
    /// @param out_tonemap [out] Receives the handle; left zeroed on failure.
    KE_RENDER_TONEMAP_API ke_result ke_render_tonemap_create(
        const ke_render_context *context, ke_render_tonemap_handle *out_tonemap);

#ifdef __cplusplus
}
#endif

#endif
