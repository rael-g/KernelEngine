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
#include <kernel_engine/runtime/runtime.h>

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

    typedef struct ke_render_gbuffer ke_render_gbuffer;

    /// [owner]
    typedef struct ke_render_gbuffer_handle
    {
        ke_render_gbuffer *ref;
        void (*destroy)(ke_render_gbuffer *self);
    } ke_render_gbuffer_handle;

    /// Registers the pass's render-phase system. A missing runtime, service or device fails as an
    /// invalid argument.
    /// It writes the frame's depth and albedo, normal and emissive targets each the size of the
    /// backbuffer.
    /// @param context [borrowed] The parts the pass is built on; read during the call.
    /// @param out_resources [out] Receives the ids of the targets it writes; every id
    ///                      KE_COMPONENT_INVALID on failure.
    /// @param out_gbuffer [out] Receives the handle; left zeroed on failure.
    KE_RENDER_GBUFFER_API ke_result ke_render_gbuffer_create(
        const ke_render_context *context, ke_render_gbuffer_resources *out_resources, ke_render_gbuffer_handle *out_gbuffer);

#ifdef __cplusplus
}
#endif

#endif
