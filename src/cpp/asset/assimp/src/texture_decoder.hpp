#pragma once

#include <kernel_engine/asset/asset_loader.h>
#include <kernel_engine/logger/logger.h>
#include <kernel_engine/allocator/allocator.h>
#include <string>

struct aiTexture;

namespace kernel_engine::asset::assimp::TextureDecoder
{

ke_result DecodeExternal(const std::string& path, ke_allocator* allocator, ke_logger* logger, ke_texture_data* out_data);
ke_result DecodeEmbedded(const aiTexture* embedded, ke_allocator* allocator, ke_logger* logger, ke_texture_data* out_data);

} // namespace kernel_engine::asset::assimp::TextureDecoder
