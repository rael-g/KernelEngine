#ifndef KERNEL_ENGINE_ASSET_STB_IMAGE_ASSET_STB_IMAGE_PARTS_H_
#define KERNEL_ENGINE_ASSET_STB_IMAGE_ASSET_STB_IMAGE_PARTS_H_

#include <kernel_engine/asset/stb_image/stb_image_loader.h>
#include <kernel_engine/assembly/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_asset_stb_image contains: `image_loader_stb`, providing ke_image_loader, with the slot `io`.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_ASSET_STB_IMAGE_API const ke_part *ke_asset_stb_image_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
