#ifndef KERNEL_ENGINE_RENDER_UI_UI_SYSTEMS_CREATE_H_
#define KERNEL_ENGINE_RENDER_UI_UI_SYSTEMS_CREATE_H_

#include <kernel_engine/module/module.h>
#include <kernel_engine/result/result.h>
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

    /// Creates the module of @p ui: attaching it registers, in the render schedule, "render.ui.labels"
    /// in the render prepare set, which lays out each label's text, and "render.ui" in the render queue
    /// set, which declares, at KE_RENDER_STAGE_OVERLAY, the pass drawing the quads and the labels over the
    /// frame's colour.
    /// @param ui [borrowed] Created by this library; must outlive the module.
    /// @param out_module [out] Receives the module; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; KE_RESULT_OUT_OF_MEMORY.
    KE_RENDER_UI_API ke_result ke_render_ui_systems_create(ke_render_ui *ui, ke_module_handle *out_module);

#ifdef __cplusplus
}
#endif

#endif
