#ifndef KERNEL_ENGINE_ASSET_STB_IMAGE_STB_IMAGE_LOADER_H_
#define KERNEL_ENGINE_ASSET_STB_IMAGE_STB_IMAGE_LOADER_H_

#include <kernel_engine/asset/image_loader.h>
#include <kernel_engine/io/io.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_ASSET_STB_IMAGE_EXPORT
        #define KE_ASSET_STB_IMAGE_API __declspec(dllexport)
    #elif defined(KE_ASSET_STB_IMAGE_STATIC)
        #define KE_ASSET_STB_IMAGE_API
    #else
        #define KE_ASSET_STB_IMAGE_API __declspec(dllimport)
    #endif
#else
    #define KE_ASSET_STB_IMAGE_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/** Construction parameters for ke_image_loader_stb_create. */
typedef struct ke_image_loader_stb_params
{
    /// [provider] The io each load reads its file through; required, borrowed for the lifetime of
    /// the loader.
    ke_io *io;
} ke_image_loader_stb_params;

/// @brief Creates a ke_image_loader that reads a file through @p params' io, decodes it with
///        stb_image and logs a failed decode's reason.
/// @param params [borrowed] The io.
/// @param out_loader [out] Receives the loader; left zeroed on failure.
/// @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p params, io or @p out_loader, or
///         KE_RESULT_OUT_OF_MEMORY.
KE_ASSET_STB_IMAGE_API ke_result ke_image_loader_stb_create(const ke_image_loader_stb_params *params,
                                                            ke_image_loader_handle *out_loader);

#ifdef __cplusplus
}
#endif

#endif
