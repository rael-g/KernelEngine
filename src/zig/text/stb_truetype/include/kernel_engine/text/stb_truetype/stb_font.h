#ifndef KERNEL_ENGINE_TEXT_STB_TRUETYPE_STB_FONT_H_
#define KERNEL_ENGINE_TEXT_STB_TRUETYPE_STB_FONT_H_

#include <kernel_engine/io/io.h>
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

/** Construction parameters for ke_font_loader_stb_create. */
typedef struct ke_font_loader_stb_params
{
    /// [provider] The io each load reads its font file through; required, borrowed for the
    /// lifetime of the loader.
    ke_io *io;
} ke_font_loader_stb_params;

/**
 * @brief Creates a ke_font_loader that reads font files through @p params' io. Callable from any
 *        thread (CPU only).
 * @param params [borrowed] The io.
 * @param out_loader [out] Receives the loader; left zeroed on failure.
 * @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p params, io or @p out_loader, or
 *         KE_RESULT_OUT_OF_MEMORY.
 */
KE_TEXT_STB_TRUETYPE_API ke_result ke_font_loader_stb_create(const ke_font_loader_stb_params *params,
                                                             ke_font_loader_handle *out_loader);

#ifdef __cplusplus
}
#endif

#endif
