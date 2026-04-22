#define STB_IMAGE_IMPLEMENTATION
#include <stb_image.h>

#include "TextureDecoder.hpp"
#include "InternalHelpers.hpp"
#include <assimp/texture.h>
#include <cstring>
#include <cstdlib>

namespace kernel_engine::asset::assimp::TextureDecoder
{

using namespace detail;

static ke_result CopyAndFree(uint8_t* raw, int w, int h, ke_allocator* allocator, ke_logger* logger, ke_texture_data* out_data)
{
    if (!raw)
    {
        log_warn(logger, "Failed to load texture; using white fallback");
        raw = (uint8_t*)malloc(4);
        if (raw) { raw[0] = raw[1] = raw[2] = raw[3] = 0xFF; }
        w = h = 1;
    }

    if (!raw) return KE_ERROR_OUT_OF_MEMORY;

    size_t byte_count = (size_t)w * h * 4;
    out_data->pixels = (uint8_t*)ke_alloc(allocator, byte_count);
    if (out_data->pixels)
    {
        memcpy(out_data->pixels, raw, byte_count);
    }
    
    out_data->width  = (uint32_t)w;
    out_data->height = (uint32_t)h;

    free(raw);

    return out_data->pixels ? KE_OK : KE_ERROR_OUT_OF_MEMORY;
}

ke_result DecodeExternal(const std::string& path, ke_allocator* allocator, ke_logger* logger, ke_texture_data* out_data)
{
    int w = 0, h = 0, ch = 0;
    uint8_t* raw = stbi_load(path.c_str(), &w, &h, &ch, 4);
    if (raw)
    {
        copy_string(out_data->path, sizeof(out_data->path), path.c_str());
    }
    return CopyAndFree(raw, w, h, allocator, logger, out_data);
}

ke_result DecodeEmbedded(const aiTexture* et, ke_allocator* allocator, ke_logger* logger, ke_texture_data* out_data)
{
    int w = 0, h = 0, ch = 0;
    uint8_t* raw = nullptr;

    if (et->mHeight == 0)
    {
        // Compressed in-memory (PNG/JPEG inside GLB)
        raw = stbi_load_from_memory(
            reinterpret_cast<const stbi_uc*>(et->pcData),
            (int)et->mWidth, &w, &h, &ch, 4);
    }
    else
    {
        // Already raw ARGB8888 — convert to RGBA8
        w = (int)et->mWidth; h = (int)et->mHeight;
        raw = (uint8_t*)malloc((size_t)w * h * 4);
        if (raw)
        {
            const aiTexel* src = et->pcData;
            for (int px = 0; px < w * h; ++px)
            {
                raw[px * 4 + 0] = src[px].r;
                raw[px * 4 + 1] = src[px].g;
                raw[px * 4 + 2] = src[px].b;
                raw[px * 4 + 3] = src[px].a;
            }
        }
    }

    return CopyAndFree(raw, w, h, allocator, logger, out_data);
}

} // namespace kernel_engine::asset::assimp::TextureDecoder
