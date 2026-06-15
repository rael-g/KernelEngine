#pragma once

#include <kernel_engine/asset/image_loader.h>
#include <kernel_engine/asset/stb_image/asset_export.h>

#ifdef __cplusplus
extern "C" {
#endif

/// @brief Construction parameters for the stb_image-backed image loader.
typedef struct ke_image_loader_stb_params
{
    struct ke_allocator *allocator; ///< Allocator used for the loader struct + decoded pixel data
    struct ke_logger    *logger;    ///< Optional; may be NULL
} ke_image_loader_stb_params;

/// @brief Creates a stb_image-backed ke_image_loader.
/// @param params  Non-null construction parameters.
/// @param out     Receives the created loader on success.
KE_ASSET_STB_IMAGE_API ke_result ke_image_loader_stb_create(
    const ke_image_loader_stb_params *params,
    ke_image_loader **out);

#ifdef __cplusplus
}
#endif
