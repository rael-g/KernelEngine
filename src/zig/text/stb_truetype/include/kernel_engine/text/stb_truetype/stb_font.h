#ifndef KERNEL_ENGINE_TEXT_STB_TRUETYPE_STB_FONT_H_
#define KERNEL_ENGINE_TEXT_STB_TRUETYPE_STB_FONT_H_

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

/// @brief Creates a ke_font_loader. Callable from any thread (CPU only).
/// @return Handle whose @c ref is NULL on failure.
KE_TEXT_STB_TRUETYPE_API ke_font_loader_handle ke_font_loader_stb_create(ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif
