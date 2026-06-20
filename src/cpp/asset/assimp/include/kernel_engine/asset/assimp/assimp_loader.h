#pragma once

#include <kernel_engine/asset/asset_loader.h>
#include <kernel_engine/asset/assimp/asset_export.h>

#ifdef __cplusplus
extern "C" {
#endif

/// @brief Construction parameters for the Assimp asset loader.
typedef struct ke_asset_loader_assimp_params
{
    struct ke_logger    *logger;    ///< Optional; may be NULL
} ke_asset_loader_assimp_params;

/// @brief Creates an Assimp-backed ke_asset_loader.
/// @param params  Non-null construction parameters.
/// @return        Handle whose @c ref is NULL on failure.
KE_ASSET_ASSIMP_API ke_asset_loader_handle ke_asset_loader_assimp_create(
    const ke_asset_loader_assimp_params *params,
    ke_error **out_error);

#ifdef __cplusplus
}
#endif
