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

// A screen-space text label. Text/anchor/offset/color/font are the caller's
// input (a node's own properties, written on bind/update); glyph_count and
// glyphs[] are output, written each KE_PHASE_UPDATE tick by the "render.ui.labels"
// system this domain registers, and read by "render.ui" (KE_PHASE_RENDER) to
// draw them — the same sim-writes/render-reads split every other render
// component uses, so there is no per-glyph entity, no CPU-side accumulator,
// no pool to grow or reuse.
//
// text/glyphs are fixed-size, like ke_name_component's char name[64] elsewhere
// in this codebase: an ECS component is a C ABI struct, so a caller-provided
// ceiling is unavoidable here, not a design choice. 256 covers any UI label a
// game actually authors; text/glyphs beyond the cap are silently truncated
// rather than overflowing.
#define KE_LABEL_MAX_TEXT 256
#define KE_LABEL_MAX_GLYPHS 256

    typedef struct ke_label_glyph_quad
    {
        float dst_x, dst_y, dst_w, dst_h;
        float u0, v0, u1, v1;
    } ke_label_glyph_quad;

    typedef struct ke_label_component
    {
        ke_ui_font_handle font;
        float             anchor[2];
        float             offset[2];
        float             color[4];
        char              text[KE_LABEL_MAX_TEXT];

        uint32_t            glyph_count;
        ke_label_glyph_quad glyphs[KE_LABEL_MAX_GLYPHS];
    } ke_label_component;

#define KE_COMPONENT_NAME_LABEL "label"

    // UI overlay pass — screen-space quad batching (sprite batching, premultiplied
    // alpha), drawn after tonemap so it composites over the rendered scene. Game
    // code queues a quad by attaching the "ui_quad" ECS component (declared write
    // access from the producer's own system) to an entity — the same channel
    // every other render-phase pass consumes sim-written data through, resolved
    // and extracted by the runtime before this pass's wave. No CPU-side
    // accumulator, no ui_quad/text_quad vtable call, no reset.
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

    // Creates the UI overlay pass and registers it as a runtime system.
    // `runtime`/`ecs`/`core`/`device` are borrowed. bb_cid is the "backbuffer" cid
    // the aggregator already resolved; cmd_slot is this pass's frame command-buffer
    // slot (must come after whatever writes "backbuffer" last, e.g. tonemap).
    // Handle's ref is NULL on failure.
    KE_RENDER_UI_API ke_render_ui_handle ke_render_ui_create(
        ke_runtime *runtime, ke_ecs *ecs, ke_render_service *core, ke_gpu_device *device,
        ke_ndc_convention ndc, ke_component_id bb_cid, uint32_t cmd_slot,
        ke_error **out_error);

#ifdef __cplusplus
}
#endif
