#ifndef KERNEL_ENGINE_RENDER_GBUFFER_GBUFFER_CREATE_H_
#define KERNEL_ENGINE_RENDER_GBUFFER_GBUFFER_CREATE_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
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

    typedef struct ke_render_gbuffer_handle
    {
        ke_render_gbuffer *ref;
        void (*destroy)(ke_render_gbuffer *self);
    } ke_render_gbuffer_handle;

    /// What the gbuffer pass writes, besides the frame's depth. The names are copied.
    typedef struct ke_render_gbuffer_params
    {
        ke_runtime        *runtime; ///< Registers the pass's system; borrowed, must outlive it.
        ke_render_service *service; ///< Holds the resources it writes; borrowed.
        ke_gpu_device     *device;  ///< Borrowed.
        ke_component_id    mesh_cid;
        ke_component_id    world_transform_cid;
        ke_component_id    camera_cid;
        ke_component_id    frame_cid;
        /// [utf8] The group it writes: albedo, normal and emissive under the suffixes of
        /// kernel_engine/render/resource_groups.h, each declared the size of the backbuffer.
        const char *output;
    } ke_render_gbuffer_params;

    /// Registers the pass's render-phase system. A missing runtime, service, device or output
    /// fails as an invalid argument; the handle's ref is NULL on failure.
    KE_RENDER_GBUFFER_API ke_render_gbuffer_handle ke_render_gbuffer_create(
        const ke_render_gbuffer_params *params, ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif
