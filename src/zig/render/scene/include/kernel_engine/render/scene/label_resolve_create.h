#ifndef KERNEL_ENGINE_RENDER_SCENE_LABEL_RESOLVE_CREATE_H_
#define KERNEL_ENGINE_RENDER_SCENE_LABEL_RESOLVE_CREATE_H_

#include <kernel_engine/asset/asset_resolver.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/render/context.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/ui/ui.h>
#include <kernel_engine/render/ui/ui_create.h>
#include <kernel_engine/module/module.h>

#ifndef KE_RENDER_SCENE_API
    #if defined(_WIN32) || defined(__CYGWIN__)
        #ifdef KE_RENDER_SCENE_EXPORT
            #define KE_RENDER_SCENE_API __declspec(dllexport)
        #elif defined(KE_RENDER_SCENE_STATIC)
            #define KE_RENDER_SCENE_API
        #else
            #define KE_RENDER_SCENE_API __declspec(dllimport)
        #endif
    #else
        #define KE_RENDER_SCENE_API __attribute__((visibility("default")))
    #endif
#endif

#ifdef __cplusplus
extern "C"
{
#endif




    /// Makes the label resolve. Attached, its system "render.label.resolve" gives each label of the main
    /// world, in the update set, the font it names.
    /// @param context [borrowed] The parts it is built on; read during the call.
    /// @param ui Registers the font; borrowed, must outlive it.
    /// @param resolver [optional] Reads the font a label names; borrowed. Without it every label is
    ///                 reported.
    /// @param default_font [borrowed,optional,utf8] The font a label that names none draws with;
    ///        copied. NULL leaves such a label without text.
    /// @param out_module [out] Receives the resolve; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a NULL context, scene, service or ui;
    ///         KE_RESULT_OUT_OF_MEMORY.
    KE_RENDER_SCENE_API ke_result ke_render_label_resolve_create(
        const ke_render_context *context, ke_render_ui *ui, ke_asset_resolver *resolver,
        const char *default_font, ke_module_handle *out_module);

#ifdef __cplusplus
}
#endif

#endif
