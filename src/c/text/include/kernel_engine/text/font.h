#ifndef KERNEL_ENGINE_TEXT_FONT_H_
#define KERNEL_ENGINE_TEXT_FONT_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/common/export.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_FONT_LOADER "ke_font_loader"

    /// @brief Per-glyph layout + atlas-sampling info, in pixels at the baked size.
    /// `bearing_x` shifts the quad right of the pen; `bearing_y` shifts up from the baseline.
    /// `width`/`height` is the quad size; `u0,v0,u1,v1` is the source rect in the atlas.
    typedef struct ke_glyph_metrics {
        uint32_t codepoint;
        float    u0, v0, u1, v1;
        float    bearing_x, bearing_y;
        float    width, height;
        float    advance_x;
    } ke_glyph_metrics;

    /// @brief CPU-side font data produced by a loader. Caller owns; release via the loader's
    /// free_font. Atlas is RGBA8 (white RGB + alpha from coverage) so it goes through
    /// ke_render.create_texture_rgba without a new texture format.
    typedef struct ke_font_data {
        uint8_t          *atlas_rgba;     ///< width * height * 4 bytes
        uint32_t          atlas_width;
        uint32_t          atlas_height;
        ke_glyph_metrics *glyphs;          ///< glyph_count entries
        uint32_t          glyph_count;
        float             line_height;     ///< Recommended line spacing in pixels
        float             ascent;          ///< Pixels above baseline to top of tallest glyph
    } ke_font_data;

    /// @brief ABI-stable vtable for decoding font files (TTF/OTF/…) on CPU. Async dispatch is
    /// the caller's concern (C# wraps with Task.Run on a worker); this contract stays minimal.
    /// Mirrors the ke_image_loader pattern — load returns raw bytes + metadata, texture upload
    /// happens later via ke_render.
    typedef struct ke_font_loader
    {
        void *handle;

        /// @brief Destroys the loader.
        void (*destroy)(struct ke_font_loader *self);

        /// @brief Loads @p path and bakes a glyph atlas at @p pixel_size for the codepoint range
        /// [first_codepoint, first_codepoint + codepoint_count). On success allocates a
        /// ke_font_data (atlas RGBA8 + metrics) the caller releases via free_font.
        ke_result (*load_font)(struct ke_font_loader *self,
                               const char *path,
                               float pixel_size,
                               uint32_t first_codepoint,
                               uint32_t codepoint_count,
                               uint32_t atlas_size,
                               ke_font_data **out,
                               ke_error **out_error);

        /// @brief Frees a ke_font_data previously returned by load_font.
        void (*free_font)(struct ke_font_loader *self, ke_font_data *data);

    } ke_font_loader;

    typedef struct ke_font_loader_handle
    {
        ke_font_loader *ref;
        void (*destroy)(ke_font_loader *self);
    } ke_font_loader_handle;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_TEXT_FONT_H_
