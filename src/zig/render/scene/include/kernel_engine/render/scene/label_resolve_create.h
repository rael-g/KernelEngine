#ifndef KERNEL_ENGINE_RENDER_SCENE_LABEL_RESOLVE_CREATE_H_
#define KERNEL_ENGINE_RENDER_SCENE_LABEL_RESOLVE_CREATE_H_

#include <kernel_engine/settings/settings.h>
#include <kernel_engine/asset/asset_resolver.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/scene_resolve.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/ui/ui.h>
#include <kernel_engine/render/ui/ui_create.h>
#include <kernel_engine/part/part.h>
#include <kernel_engine/schedule/schedule.h>

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

    /// Makes the label resolve, whose system "render.label.resolve", in @p update_set of @p update, gives each
    /// label of the main world the font it names. Every argument but @p out_resolve must outlive it.
    /// @param ui Registers the font.
    /// @param resolver [optional] Reads the font a label names. Without it every label is reported.
    /// @param settings [borrowed] Read once. `default_font`, a string, default empty: the font a label
    ///        that names none draws with; empty leaves such a label without text.
    /// @param out_resolve [out] Receives the resolve, whose destroy unregisters the system; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a NULL pointer other than @p resolver, or a setting that is
    ///         unknown or of another type; KE_RESULT_OUT_OF_MEMORY; the code of the schedule that refused the
    ///         system.
    KE_RENDER_SCENE_API ke_result ke_render_label_resolve_create(
        ke_render_service *service, ke_render_scene_resolve *scene, ke_render_ui *ui, ke_asset_resolver *resolver,
        ke_schedule *update, ke_schedule_set_id update_set, ke_settings *settings, ke_owner *out_resolve);

#ifdef __cplusplus
}
#endif

#endif
