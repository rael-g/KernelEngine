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

/// @brief Creates a ke_image_loader that reads a file through @p io, decodes it with
///        stb_image and logs a failed decode's reason.
/// @param io [borrowed] The io it reads through; borrowed for the lifetime of the loader.
/// @param out_loader [out] Receives the loader; left zeroed on failure.
/// @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p io or @p out_loader, or
///         KE_RESULT_OUT_OF_MEMORY.
KE_ASSET_STB_IMAGE_API ke_result ke_image_loader_stb_create(ke_io *io, ke_image_loader_handle *out_loader);

#ifdef __cplusplus
}
#endif

#endif
