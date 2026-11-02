#ifndef KERNEL_ENGINE_RENDER_UI_UI_H_
#define KERNEL_ENGINE_RENDER_UI_UI_H_

#include <kernel_engine/render/handles.h>
#include <kernel_engine/render/ui/components.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/text/font.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** [interface] The ui pass as a font registry. */
    typedef struct ke_render_ui
    {
        void *handle;

        /**
         * Registers a font's glyph table, deduped by `key`: a resident key retains and
         * returns the existing handle without copying `glyphs` again. `glyphs` is
         * copied; the caller may free its own copy after this returns.
         * @param key [utf8]
         * @param glyphs [borrowed,array_of:glyph_count]
         * @param out_font [out] Receives the font; KE_UI_FONT_NONE on failure.
         */
        ke_result (*load_font)(struct ke_render_ui *self, const char *key,
                               ke_texture_handle atlas, const ke_glyph_metrics *glyphs,
                               uint32_t glyph_count, float line_height, float ascent,
                               ke_ui_font_handle *out_font);
    } ke_render_ui;

    /// [interface] [owner]
    typedef struct ke_render_ui_handle
    {
        ke_render_ui *ref;
        void (*destroy)(ke_render_ui *self);
    } ke_render_ui_handle;

#ifdef __cplusplus
}
#endif

#endif
