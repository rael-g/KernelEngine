#pragma once

#include <kernel_engine/asset/image_loader.h>

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

/// @brief Construction parameters for the stb_image-backed image loader.
typedef struct ke_image_loader_stb_params
{
    struct ke_logger    *logger;    ///< Optional; may be NULL
} ke_image_loader_stb_params;

/// @brief Creates a stb_image-backed ke_image_loader.
/// @param params  Non-null construction parameters.
/// @return        Handle whose @c ref is NULL on failure.
KE_ASSET_STB_IMAGE_API ke_image_loader_handle ke_image_loader_stb_create(
    const ke_image_loader_stb_params *params,
    ke_error **out_error);

#ifdef __cplusplus
}
#endif
