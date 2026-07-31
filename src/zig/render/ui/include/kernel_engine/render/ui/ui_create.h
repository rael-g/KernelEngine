#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/handles.h>
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

    typedef struct ke_ui_font_handle
    {
        uint32_t bits;
    } ke_ui_font_handle;

#ifndef CLANGSHARP
#define KE_UI_FONT_NONE ((ke_ui_font_handle){ UINT32_MAX })
#endif

    // UI overlay pass — screen-space quad batching (sprite batching, premultiplied
    // alpha), drawn after tonemap so it composites over the rendered scene. Unlike
    // the fire-and-forget passes (tonemap/skybox), game code queues quads into this
    // plugin at runtime via ui_quad — so it needs a real vtable, not just create/destroy.
    typedef struct ke_render_ui
    {
        void *handle;

        // Queues a screen-space quad for this frame — accumulated CPU-side and
        // drawn (batched by texture) when the "render.ui" system runs, then reset.
        // dst_x/y/w/h are pixel-space (top-left origin); uv0..3 = (u0,v0,u1,v1);
        // color is 4 floats (premultiplied r,g,b,a) by pointer, not by value —
        // see ke_render_module_ui_quad for why.
        void (*ui_quad)(struct ke_render_ui *self, ke_texture_handle texture,
                        float dst_x, float dst_y, float dst_w, float dst_h,
                        float uv0, float uv1, float uv2, float uv3,
                        const float color[4]);

        /**
         * Registers a font's glyph table for text_quad, deduped by `key` (same
         * upload-key convention as ke_render_service's upload_* — a resident key
         * retains and returns the existing handle without copying `glyphs` again).
         * `glyphs` is copied; the caller may free its own copy after this returns.
         * KE_UI_FONT_NONE on failure.
         * @param key [utf8]
         * @param glyphs [borrowed,array_of:glyph_count]
         */
        ke_ui_font_handle (*load_font)(struct ke_render_ui *self, const char *key,
                                       ke_texture_handle atlas, const ke_glyph_metrics *glyphs,
                                       uint32_t glyph_count, float line_height, float ascent,
                                       ke_error **out_error);

        /**
         * Expands @p text into one ui_quad call per glyph (batched the same way a
         * direct ui_quad caller's quads are), advancing the pen from @p origin_x
         * with @p baseline_y as each glyph's baseline. An unknown codepoint
         * advances the pen by a quarter of the font's line height and emits
         * nothing. No line wrapping; an embedded newline is not treated specially.
         * @param font [borrowed]
         * @param text [utf8]
         */
        void (*text_quad)(struct ke_render_ui *self, ke_ui_font_handle font, const char *text,
                          float origin_x, float baseline_y, const float color[4]);
    } ke_render_ui;

    typedef struct ke_render_ui_handle
    {
        ke_render_ui *ref;
        void (*destroy)(ke_render_ui *self);
    } ke_render_ui_handle;

    // Creates the UI overlay pass and registers it as a runtime system.
    // `runtime`/`core`/`device` are borrowed. bb_cid is the "backbuffer" cid the
    // aggregator already resolved; cmd_slot is this pass's frame command-buffer
    // slot (must come after whatever writes "backbuffer" last, e.g. tonemap).
    // Handle's ref is NULL on failure.
    KE_RENDER_UI_API ke_render_ui_handle ke_render_ui_create(
        ke_runtime *runtime, ke_render_service *core, ke_gpu_device *device,
        ke_ndc_convention ndc, ke_component_id bb_cid, uint32_t cmd_slot,
        ke_error **out_error);

#ifdef __cplusplus
}
#endif
