#ifndef KERNEL_ENGINE_ASSET_ASSIMP_ASSET_ASSIMP_PARTS_H_
#define KERNEL_ENGINE_ASSET_ASSIMP_ASSET_ASSIMP_PARTS_H_

#include <kernel_engine/asset/assimp/assimp_loader.h>
#include <kernel_engine/assembly/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_asset_assimp contains: `asset_loader_assimp`, providing ke_asset_loader, with the slot `io`.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_ASSET_ASSIMP_API const ke_part *ke_asset_assimp_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
