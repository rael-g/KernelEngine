#ifndef KERNEL_ENGINE_RENDER_UI_COMPONENTS_H_
#define KERNEL_ENGINE_RENDER_UI_COMPONENTS_H_

#include <kernel_engine/render/handles.h>
#include <kernel_engine/spatial/transform.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_ui_font_handle
    {
        uint32_t bits;
    } ke_ui_font_handle;

#ifndef CLANGSHARP
#define KE_UI_FONT_NONE ((ke_ui_font_handle){ KE_HANDLE_NONE })
/// A font the label asked for and the engine could not produce. Distinct from
/// KE_UI_FONT_NONE, which means no font was asked for.
#define KE_UI_FONT_FAILED ((ke_ui_font_handle){ UINT32_MAX })
#endif

    /// [value]
    /// One shaped glyph: the screen-space rectangle it draws to and the atlas
    /// rectangle it samples from.
    typedef struct ke_label_glyph_quad
    {
        float dst_x, dst_y, dst_w, dst_h;
        float u0, v0, u1, v1;
    } ke_label_glyph_quad;

#define KE_LABEL_MAX_TEXT 256
#define KE_LABEL_MAX_GLYPHS 256

    /// A single screen-space UI quad. A quad of zero size is skipped.
    typedef struct ke_ui_quad_component
    {
        /// Full generational texture handle bits; UINT32_MAX = the built-in white.
        uint32_t texture_bits;
        float    dst_x, dst_y, dst_w, dst_h;
        float    u0, v0, u1, v1;
        float    color[4]; ///< [default:1 1 1 1] Premultiplied alpha RGBA.
    } ke_ui_quad_component;

    /// [node:Label,base:Node3D]
    /// A screen-space text label. Text, anchor, offset, color and font are the
    /// caller's input; glyph_count and glyphs[] are output, written each
    /// KE_PHASE_UPDATE tick.
    typedef struct ke_label_component
    {
        /// Font file to draw with.
        char              font[128];
        /// Size the font is baked at, in pixels.
        float             font_size; ///< [default:32]

        /// [idiom,name:font_handle] Resolved from `font`.
        ke_ui_font_handle font_handle;
        /// Anchor in normalized [0..1] of the backbuffer. (0,0) = top-left, (1,1) = bottom-right.
        float             anchor[2];
        /// Pixel offset applied AFTER anchor positioning.
        float             offset[2];
        float             color[4]; ///< [default:1 1 1 1]
        char              text[KE_LABEL_MAX_TEXT];

        /// [idiom,output] Written by the engine each tick; a node authoring it would
        /// have the value overwritten on the next tick.
        uint32_t            glyph_count;
        /// [idiom,output] Shaped output, see glyph_count.
        ke_label_glyph_quad glyphs[KE_LABEL_MAX_GLYPHS];
    } ke_label_component;

#ifdef __cplusplus
}
#endif

#endif
