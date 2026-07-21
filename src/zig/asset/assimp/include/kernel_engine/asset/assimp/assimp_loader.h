// ke_asset_loader_assimp_create — factory for the Assimp-backed asset loader
// (the only export this plugin has; everything else it offers is reached
// through the ke_asset_loader vtable the factory returns).

#pragma once

#include <kernel_engine/asset/asset_loader.h>

#ifndef KE_ASSET_ASSIMP_API
#  if defined(_WIN32) || defined(__CYGWIN__)
#    if defined(KE_ASSET_ASSIMP_STATIC)
#      define KE_ASSET_ASSIMP_API
#    elif defined(KE_ASSET_ASSIMP_EXPORT)
#      define KE_ASSET_ASSIMP_API __declspec(dllexport)
#    else
#      define KE_ASSET_ASSIMP_API __declspec(dllimport)
#    endif
#  else
#    define KE_ASSET_ASSIMP_API __attribute__((visibility("default")))
#  endif
#endif

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
