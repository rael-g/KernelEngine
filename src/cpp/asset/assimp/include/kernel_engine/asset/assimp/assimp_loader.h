#pragma once

#include <kernel_engine/kernel/asset/asset_loader.h>
#include <kernel_engine/kernel/context/types.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef KE_ASSET_ASSIMP_API
    #ifdef KE_ASSET_ASSIMP_STATIC
        #define KE_ASSET_ASSIMP_API
    #else
        #ifdef KE_ASSET_ASSIMP_EXPORT
            #define KE_ASSET_ASSIMP_API KE_HELPER_EXPORT
        #else
            #define KE_ASSET_ASSIMP_API KE_HELPER_IMPORT
        #endif
    #endif
#endif

/// @brief Construction parameters for the Assimp asset loader.
typedef struct ke_asset_loader_assimp_params
{
    struct ke_allocator *allocator; ///< Allocator used for all model data allocations
    struct ke_logger    *logger;    ///< Optional; may be NULL
} ke_asset_loader_assimp_params;

/// @brief Creates an Assimp-backed ke_asset_loader.
/// @param params  Non-null construction parameters.
/// @param out     Receives the created loader on success.
KE_ASSET_ASSIMP_API ke_result ke_asset_loader_assimp_create(
    const ke_asset_loader_assimp_params *params,
    ke_asset_loader **out);

#ifdef __cplusplus
}
#endif
