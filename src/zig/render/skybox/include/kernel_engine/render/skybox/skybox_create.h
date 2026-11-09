#ifndef KERNEL_ENGINE_RENDER_SKYBOX_SKYBOX_CREATE_H_
#define KERNEL_ENGINE_RENDER_SKYBOX_SKYBOX_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/render/context.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/camera.h>
#include <kernel_engine/runtime/runtime.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_SKYBOX_EXPORT
        #define KE_RENDER_SKYBOX_API __declspec(dllexport)
    #elif defined(KE_RENDER_SKYBOX_STATIC)
        #define KE_RENDER_SKYBOX_API
    #else
        #define KE_RENDER_SKYBOX_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_SKYBOX_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_render_skybox ke_render_skybox;

    /// [owner]
    typedef struct ke_render_skybox_handle
    {
        ke_render_skybox *ref;
        void (*destroy)(ke_render_skybox *self);
    } ke_render_skybox_handle;

    /// Registers the pass's render-phase system. A missing runtime, service, device or camera
    /// fails as an invalid argument.
    /// It joins the chain at KE_RENDER_STAGE_SKY and draws over the frame's color where the frame's
    /// depth is at the far plane.
    /// @param context [borrowed] The parts the pass is built on; read during the call.
    /// @param out_skybox [out] Receives the handle; left zeroed on failure.
    KE_RENDER_SKYBOX_API ke_result ke_render_skybox_create(
        const ke_render_context *context, ke_render_skybox_handle *out_skybox);

#ifdef __cplusplus
}
#endif

#endif
