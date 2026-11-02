#ifndef KERNEL_ENGINE_RENDER_GBUFFER_GBUFFER_CREATE_H_
#define KERNEL_ENGINE_RENDER_GBUFFER_GBUFFER_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/frame.h>
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

    /// [bag] What the gbuffer pass writes, besides the frame's depth. The names are copied.
    typedef struct ke_render_gbuffer_params
    {
        ke_runtime        *runtime; ///< Registers the pass's system; borrowed, must outlive it.
        ke_render_service *service; ///< Holds the resources it writes; borrowed.
        ke_gpu_device     *device;        ke_render_scene_resolve *scene; ///< Names the components the pass reads; borrowed.
        ke_render_frame   *frame;  ///< The pass runs inside its frame; borrowed.
        /// [utf8] The group it writes: albedo, normal and emissive under the suffixes of
        /// kernel_engine/render/resource_groups.h, each declared the size of the backbuffer.
        const char *output;
    } ke_render_gbuffer_params;

    /// Registers the pass's render-phase system. A missing runtime, service, device or output
    /// fails as an invalid argument.
    /// @param out_gbuffer [out] Receives the handle; left zeroed on failure.
    KE_RENDER_GBUFFER_API ke_result ke_render_gbuffer_create(
        const ke_render_gbuffer_params *params, ke_render_gbuffer_handle *out_gbuffer);

#ifdef __cplusplus
}
#endif

#endif
