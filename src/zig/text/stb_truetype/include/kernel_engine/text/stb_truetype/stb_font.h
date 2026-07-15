#pragma once

#include <kernel_engine/text/font.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_TEXT_STB_TRUETYPE_EXPORT
        #define KE_TEXT_STB_TRUETYPE_API __declspec(dllexport)
    #elif defined(KE_TEXT_STB_TRUETYPE_STATIC)
        #define KE_TEXT_STB_TRUETYPE_API
    #else
        #define KE_TEXT_STB_TRUETYPE_API __declspec(dllimport)
    #endif
#else
    #define KE_TEXT_STB_TRUETYPE_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// @brief Construction parameters for the stb_truetype-backed ke_font_loader.
typedef struct ke_font_loader_stb_params
{
    struct ke_logger    *logger;        ///< Optional
} ke_font_loader_stb_params;

/// @brief Creates a stb_truetype-backed ke_font_loader. Callable from any thread (CPU only).
/// Atlas upload + Font class assembly happen later in C# (see KernelEngine.Text.StbTrueType /
/// KernelEngine.Framework.Assets.LoadFontAsync).
/// @return Handle whose @c ref is NULL on failure.
KE_TEXT_STB_TRUETYPE_API ke_font_loader_handle ke_font_loader_stb_create(
    const ke_font_loader_stb_params *params,
    ke_error **out_error);

#ifdef __cplusplus
}
#endif
