#ifndef KERNEL_ENGINE_RENDER_SCENE_LABEL_RESOLVE_CREATE_H_
#define KERNEL_ENGINE_RENDER_SCENE_LABEL_RESOLVE_CREATE_H_

#include <kernel_engine/asset/asset_resolver.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/logger/logger.h>
#include <kernel_engine/render/service/render_service.h>
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

    typedef struct ke_render_label_resolve_handle
    {
        ke_render_label_resolve *ref;
        void (*destroy)(ke_render_label_resolve *self);
    } ke_render_label_resolve_handle;

    /// What the label resolve needs to give a label the font it names.
    typedef struct ke_render_label_resolve_params
    {
        ke_runtime        *runtime;   ///< Registers the system; borrowed, must outlive it.
        ke_render_service *service;   ///< Uploads the glyph atlas; borrowed, must outlive it.
        ke_render_ui      *ui;        ///< Registers the font; borrowed, must outlive it.
        /// Reads the font a label names; optional, borrowed. Without it every label is reported.
        ke_asset_resolver *resolver;
        ke_logger         *logger;    ///< Reports a font that did not resolve; optional, borrowed.
        ke_component_id    label_cid;
    } ke_render_label_resolve_params;

    /// Registers the update-phase system "render.label.resolve", which runs before the ui pass's
    /// "render.ui.labels". A missing runtime, service or ui fails as an invalid argument; the
    /// handle's ref is NULL on failure.
    KE_RENDER_SCENE_API ke_render_label_resolve_handle ke_render_label_resolve_create(
        const ke_render_label_resolve_params *params, ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif
