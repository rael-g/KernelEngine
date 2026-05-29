#ifndef KERNEL_ENGINE_KERNEL_TEXT_FONT_H_
#define KERNEL_ENGINE_KERNEL_TEXT_FONT_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/common/handles.h>
#include <kernel_engine/kernel/context/types.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_FONT "ke_font"

    /// @brief Per-glyph layout + atlas-sampling info. All measurements in pixels (atlas-baked size).
    /// `advance_x` is the pen advance; `bearing_{x,y}` shift the quad from the pen; `width/height`
    /// is the quad size; `u0,v0,u1,v1` is the source rect in the font's atlas texture.
    typedef struct ke_glyph_metrics {
        float u0, v0, u1, v1;
        float bearing_x, bearing_y;
        float width, height;
        float advance_x;
    } ke_glyph_metrics;

    /// @brief ABI-stable vtable for a font. One implementation per backend (stb_truetype today;
    /// FreeType / native shaper later). MVP supports ASCII range only; full Unicode glyph rasterization
    /// on demand comes after the layer ships.
    typedef struct ke_font
    {
        void *handle;

        /// @brief Releases backend memory + atlas texture.
        void (*destroy)(struct ke_font *self);

        /// @brief Looks up the glyph for @p codepoint. Returns true + fills @p out when present in
        /// the atlas; false otherwise (caller renders a fallback or skips).
        ke_bool (*glyph)(struct ke_font *self, uint32_t codepoint, ke_glyph_metrics *out);

        /// @brief The atlas texture (RGBA8) — bind to the UI quad shader's s_texColor sampler.
        ke_texture_handle (*atlas_texture)(struct ke_font *self);

        /// @brief Recommended line spacing for the baked pixel size (ascent + descent + line gap).
        float (*line_height)(struct ke_font *self);
    } ke_font;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_TEXT_FONT_H_
