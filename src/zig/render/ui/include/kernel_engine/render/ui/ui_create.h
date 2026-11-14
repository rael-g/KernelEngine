#ifndef KERNEL_ENGINE_RENDER_UI_UI_CREATE_H_
#define KERNEL_ENGINE_RENDER_UI_UI_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/render/context.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/frame.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/handles.h>
#include <kernel_engine/render/ui/components.h>
#include <kernel_engine/render/ui/ui.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_RENDER_UI_EXPORT
        #define KE_RENDER_UI_API __declspec(dllexport)
    #elif defined(KE_RENDER_UI_STATIC)
        #define KE_RENDER_UI_API
    #else
        #define KE_RENDER_UI_API __declspec(dllimport)
    #endif
#else
    #define KE_RENDER_UI_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    /// Makes the ui pass and registers its quad and label components in the main and the render world,
    /// with a copy of each in the extraction. Its systems come from ke_render_ui_systems_create.
    /// @param context [borrowed] The parts the pass is built on; read during the call.
    /// @param out_ui [out] Receives the handle; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT when the context or a part the pass uses is NULL; the
    ///         code of the world, the extraction or the GPU object that failed.
    KE_RENDER_UI_API ke_result ke_render_ui_create(const ke_render_context *context,
                                                   ke_render_ui_handle *out_ui);

#ifdef __cplusplus
}
#endif

#endif
