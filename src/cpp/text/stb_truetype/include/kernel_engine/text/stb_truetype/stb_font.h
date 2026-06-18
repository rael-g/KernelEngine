#pragma once

#include <kernel_engine/text/font.h>
#include <kernel_engine/text/stb_truetype/text_export.h>

#ifdef __cplusplus
extern "C" {
#endif

/// @brief Construction parameters for the stb_truetype-backed ke_font_loader.
typedef struct ke_font_loader_stb_params
{
    struct ke_allocator *allocator;     ///< Owns loader + per-load ke_font_data buffers
    struct ke_logger    *logger;        ///< Optional
} ke_font_loader_stb_params;

/// @brief Creates a stb_truetype-backed ke_font_loader. Callable from any thread (CPU only).
/// Atlas upload + Font class assembly happen later in C# (see KernelEngine.Text.StbTrueType /
/// KernelEngine.Framework.Assets.LoadFontAsync).
KE_TEXT_STB_TRUETYPE_API ke_result ke_font_loader_stb_create(
    const ke_font_loader_stb_params *params,
    ke_font_loader_handle *out,
    ke_error **out_error);

#ifdef __cplusplus
}
#endif
