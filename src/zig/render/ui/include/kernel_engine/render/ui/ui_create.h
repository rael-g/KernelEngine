#ifndef KERNEL_ENGINE_RENDER_UI_UI_CREATE_H_
#define KERNEL_ENGINE_RENDER_UI_UI_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/extraction/extraction.h>
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

    /// Makes the ui pass and registers its quad and label components in @p main and @p render, with a copy of
    /// each in @p extraction. Its systems come from ke_render_ui_systems_create. Every argument but @p out_ui
    /// must outlive the pass.
    /// @param out_ui [out] Receives the handle; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a NULL pointer; the code of the world, the extraction or
    ///         the GPU object that failed.
    KE_RENDER_UI_API ke_result ke_render_ui_create(
        ke_ecs *main, ke_ecs *render, ke_extraction *extraction, ke_render_service *service, ke_gpu_device *device,
        ke_render_frame *frame, ke_render_ui_handle *out_ui);

#ifdef __cplusplus
}
#endif

#endif
