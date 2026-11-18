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
#include <kernel_engine/module/module.h>

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

    /// Makes the skybox pass. Attached, it declares in the render queue set, at KE_RENDER_STAGE_SKY, the
    /// pass that draws the sky over the frame's color where the frame's depth is at the far plane.
    /// @param context [borrowed] The parts the pass is built on; read during the call.
    /// @param out_module [out] Receives the pass; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT when the context or a part the pass uses is NULL; the
    ///         code of the GPU object that could not be made.
    KE_RENDER_SKYBOX_API ke_result ke_render_skybox_create(
        const ke_render_context *context, ke_module_handle *out_module);

#ifdef __cplusplus
}
#endif

#endif
