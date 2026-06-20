#pragma once

#include <kernel_engine/asset/asset_loader.h>
#include <kernel_engine/logger/logger.h>
#include <string>

struct aiTexture;

namespace kernel_engine::asset::assimp::TextureDecoder
{

bool DecodeExternal(const std::string& path, ke_logger* logger, ke_texture_data* out_data);
bool DecodeEmbedded(const aiTexture* embedded, ke_logger* logger, ke_texture_data* out_data);

} // namespace kernel_engine::asset::assimp::TextureDecoder
