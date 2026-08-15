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
#endif

    typedef struct ke_label_glyph_quad
    {
        float dst_x, dst_y, dst_w, dst_h;
        float u0, v0, u1, v1;
    } ke_label_glyph_quad;

#define KE_LABEL_MAX_TEXT 256
#define KE_LABEL_MAX_GLYPHS 256

    /// A single screen-space UI quad. Producers — Label's text shaping, a game
    /// script attaching one directly — write it; the "render.ui" pass reads it
    /// through a declared query, the same sim-writes/render-reads split every
    /// other render component uses. A quad of zero size is skipped, which is how
    /// a pooled slot hides itself.
    typedef struct ke_ui_quad_component
    {
        /// Full generational texture handle bits; UINT32_MAX = the built-in white.
        uint32_t texture_bits;
        float    dst_x, dst_y, dst_w, dst_h;
        float    u0, v0, u1, v1;
        float    color[4]; ///< [default:1 1 1 1] Premultiplied alpha RGBA.
    } ke_ui_quad_component;

#define KE_COMPONENT_NAME_UI_QUAD "ui_quad"

    /// [node:Label,base:Node3D]
    /// A screen-space text label. Text/anchor/offset/color/font are the caller's
    /// input; glyph_count and glyphs[] are output, written each KE_PHASE_UPDATE
    /// tick by the "render.ui.labels" system and read by "render.ui"
    /// (KE_PHASE_RENDER) to draw them — the same sim-writes/render-reads split
    /// every other render component uses, so there is no per-glyph entity, no
    /// CPU-side accumulator, no pool to grow or reuse.
    typedef struct ke_label_component
    {
        /// Font file to draw with. Baked and registered by the native
        /// "render.label.resolve" system, which is what lets a scene name a font
        /// instead of a host handing the label a handle only its language holds.
        char              font[128];
        /// Size the font is baked at, in pixels. Part of the bake key: the same
        /// file at another size is a different atlas.
        float             font_size; ///< [default:32]

        /// [idiom,name:font_handle] Resolved from `font`; a node authoring it
        /// would name a font the overlay pass does not hold.
        ke_ui_font_handle font_handle;
        /// Anchor in normalized [0..1] of the backbuffer. (0,0) = top-left, (1,1) = bottom-right.
        float             anchor[2];
        /// Pixel offset applied AFTER anchor positioning.
        float             offset[2];
        float             color[4]; ///< [default:1 1 1 1]
        char              text[KE_LABEL_MAX_TEXT];

        /// [idiom,output] Written by "render.ui.labels"; a node authoring it would
        /// have the value overwritten on the next tick.
        uint32_t            glyph_count;
        /// [idiom,output] Shaped output, see glyph_count.
        ke_label_glyph_quad glyphs[KE_LABEL_MAX_GLYPHS];
    } ke_label_component;

#define KE_COMPONENT_NAME_LABEL "label"

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_UI_COMPONENTS_H_
