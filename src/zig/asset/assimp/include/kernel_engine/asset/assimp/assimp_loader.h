
#ifndef KERNEL_ENGINE_ASSET_ASSIMP_ASSIMP_LOADER_H_
#define KERNEL_ENGINE_ASSET_ASSIMP_ASSIMP_LOADER_H_

#include <kernel_engine/asset/asset_loader.h>
#include <kernel_engine/io/io.h>

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

/// @brief Creates a ke_asset_loader that imports models with Assimp, reading the model and every
///        file it names through @p io.
/// @param io [borrowed] The io it reads through; borrowed for the lifetime of the loader.
/// @param out_loader [out] Receives the loader; left zeroed on failure.
/// @return KE_OK, KE_RESULT_INVALID_ARGUMENT for a null @p io or @p out_loader, or
///         KE_RESULT_OUT_OF_MEMORY.
KE_ASSET_ASSIMP_API ke_result ke_asset_loader_assimp_create(ke_io *io, ke_asset_loader_handle *out_loader);

#ifdef __cplusplus
}
#endif

#endif
