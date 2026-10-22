#ifndef KERNEL_ENGINE_ASSET_STB_IMAGE_STB_IMAGE_LOADER_H_
#define KERNEL_ENGINE_ASSET_STB_IMAGE_STB_IMAGE_LOADER_H_

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

/// @brief Creates a ke_image_loader that decodes with stb_image and logs a failed decode's reason.
/// @return Handle whose @c ref is NULL when the loader cannot be allocated.
KE_ASSET_STB_IMAGE_API ke_image_loader_handle ke_image_loader_stb_create(ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif
