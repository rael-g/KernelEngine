#pragma once

#include <kernel_engine/kernel/text/font.h>
#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/text/stb_truetype/text_export.h>

#ifdef __cplusplus
extern "C" {
#endif

/// @brief Construction parameters for the stb_truetype-backed ke_font backend.
typedef struct ke_font_stb_params
{
    struct ke_allocator *allocator;     ///< Owns font struct + atlas memory
    struct ke_logger    *logger;        ///< Optional
    struct ke_render    *render;        ///< Required — atlas texture goes through render API
    const char          *ttf_path;      ///< File path; backend reads it synchronously
    float                pixel_size;    ///< Em-square size in pixels (e.g. 32)
    uint16_t             atlas_size;    ///< Square atlas dimension (e.g. 512); ASCII fits in 256
    uint32_t             first_codepoint; ///< Inclusive (MVP: 32 = space)
    uint32_t             codepoint_count; ///< MVP: 95 = printable ASCII 32..126
} ke_font_stb_params;

/// @brief Loads a TTF, bakes the requested codepoint range into an atlas, uploads the atlas
/// texture via @p params->render, returns a font vtable. Must be called on ke.render (texture
/// upload is render-thread-only). Caller destroys via the vtable's destroy().
KE_TEXT_STB_TRUETYPE_API ke_result ke_font_stb_create(
    const ke_font_stb_params *params,
    ke_font **out);

#ifdef __cplusplus
}
#endif
