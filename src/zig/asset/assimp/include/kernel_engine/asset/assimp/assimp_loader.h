
#ifndef KERNEL_ENGINE_ASSET_ASSIMP_ASSIMP_LOADER_H_
#define KERNEL_ENGINE_ASSET_ASSIMP_ASSIMP_LOADER_H_

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

/// @brief Creates a ke_asset_loader that imports models with Assimp.
/// @return Handle whose @c ref is NULL when the loader cannot be allocated.
KE_ASSET_ASSIMP_API ke_asset_loader_handle ke_asset_loader_assimp_create(ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif
