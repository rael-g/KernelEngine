#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/handles.h>
#include <kernel_engine/render/ui/components.h>
#include <kernel_engine/runtime/runtime.h>
#include <kernel_engine/text/font.h>

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

    typedef struct ke_render_ui
    {
        void *handle;

        /**
         * Registers a font's glyph table, deduped by `key` (same upload-key
         * convention as ke_render_service's upload_* — a resident key retains and
         * returns the existing handle without copying `glyphs` again). `glyphs` is
         * copied; the caller may free its own copy after this returns.
         * KE_UI_FONT_NONE on failure.
         * @param key [utf8]
         * @param glyphs [borrowed,array_of:glyph_count]
         */
        ke_ui_font_handle (*load_font)(struct ke_render_ui *self, const char *key,
                                       ke_texture_handle atlas, const ke_glyph_metrics *glyphs,
                                       uint32_t glyph_count, float line_height, float ascent,
                                       ke_error **out_error);
    } ke_render_ui;

    typedef struct ke_render_ui_handle
    {
        ke_render_ui *ref;
        void (*destroy)(ke_render_ui *self);
    } ke_render_ui_handle;

    KE_RENDER_UI_API ke_render_ui_handle ke_render_ui_create(
        ke_runtime *runtime, ke_ecs *ecs, ke_render_service *core, ke_gpu_device *device,
        ke_ndc_convention ndc, ke_component_id bb_cid, uint32_t cmd_slot,
        ke_error **out_error);

#ifdef __cplusplus
}
#endif
