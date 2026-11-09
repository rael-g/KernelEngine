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
#include <kernel_engine/runtime/runtime.h>

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

    typedef struct ke_render_label_resolve ke_render_label_resolve;

    /// [owner]
    typedef struct ke_render_label_resolve_handle
    {
        ke_render_label_resolve *ref;
        void (*destroy)(ke_render_label_resolve *self);
    } ke_render_label_resolve_handle;

    /// [bag] What the label resolve needs to give a label the font it names.
    /// [bag] The values the label resolve is created with.
    typedef struct ke_render_label_resolve_config
    {
        /// [optional,utf8] The font a label that names none draws with; copied. NULL leaves such a
        /// label without text.
        const char *default_font;
    } ke_render_label_resolve_config;

    /** [defaults] The values a caller gets when it sets nothing. */
    static const ke_render_label_resolve_config ke_render_label_resolve_config_defaults = {
        .default_font = NULL,
    };

    /// Registers the update-phase system "render.label.resolve", which runs before the ui pass's
    /// "render.ui.labels". A missing runtime, service or ui fails as an invalid argument; the
    /// handle's ref is NULL on failure.
    /// @param context [borrowed] The parts it is built on; read during the call.
    /// @param ui Registers the font; borrowed, must outlive it.
    /// @param resolver [optional] Reads the font a label names; borrowed. Without it every label is
    ///                 reported.
    /// @param config [borrowed,optional] Its values; NULL selects the defaults.
    /// @param out_resolve [out] Receives the handle; left zeroed on failure.
    KE_RENDER_SCENE_API ke_result ke_render_label_resolve_create(
        const ke_render_context *context, ke_render_ui *ui, ke_asset_resolver *resolver,
        const ke_render_label_resolve_config *config, ke_render_label_resolve_handle *out_resolve);

#ifdef __cplusplus
}
#endif

#endif
