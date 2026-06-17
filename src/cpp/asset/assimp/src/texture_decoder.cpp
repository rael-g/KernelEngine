#define STB_IMAGE_IMPLEMENTATION
#include <stb_image.h>

#include "texture_decoder.hpp"
#include "internal_helpers.hpp"
#include <assimp/texture.h>
#include <cstring>

namespace kernel_engine::asset::assimp::TextureDecoder
{

using namespace detail;

// Mixing malloc/stbi/ke_alloc across DLL boundaries crashes on Windows because each CRT
// owns its own heap. Rule here: out_data->pixels is always allocated with the project
// allocator (caller's heap); intermediate buffers are owned by whoever produced them and
// freed with that producer's matching free function.
static ke_result EncodeFallbackWhite(ke_allocator* allocator, ke_logger* logger, ke_texture_data* out_data)
{
    log_warn(logger, "Failed to load texture; using white fallback");
    out_data->pixels = (uint8_t*)ke_alloc(allocator, 4);
    if (!out_data->pixels) return KE_ERROR;
    out_data->pixels[0] = out_data->pixels[1] = out_data->pixels[2] = out_data->pixels[3] = 0xFF;
    out_data->width  = 1;
    out_data->height = 1;
    return KE_OK;
}

static ke_result CopyToAllocator(const uint8_t* raw, int w, int h, ke_allocator* allocator, ke_texture_data* out_data)
{
    size_t byte_count = (size_t)w * h * 4;
    out_data->pixels = (uint8_t*)ke_alloc(allocator, byte_count);
    if (!out_data->pixels) return KE_ERROR;
    memcpy(out_data->pixels, raw, byte_count);
    out_data->width  = (uint32_t)w;
    out_data->height = (uint32_t)h;
    return KE_OK;
}

ke_result DecodeExternal(const std::string& path, ke_allocator* allocator, ke_logger* logger, ke_texture_data* out_data)
{
    int w = 0, h = 0, ch = 0;
    uint8_t* raw = stbi_load(path.c_str(), &w, &h, &ch, 4);
    if (!raw) return EncodeFallbackWhite(allocator, logger, out_data);

    copy_string(out_data->path, sizeof(out_data->path), path.c_str());
    auto res = CopyToAllocator(raw, w, h, allocator, out_data);
    stbi_image_free(raw); // matched with stbi_load (stb's CRT)
    return res;
}

ke_result DecodeEmbedded(const aiTexture* et, ke_allocator* allocator, ke_logger* logger, ke_texture_data* out_data)
{
    if (et->mHeight == 0)
    {
        // Compressed in-memory (PNG/JPEG inside GLB) — stb owns the decode buffer.
        int w = 0, h = 0, ch = 0;
        uint8_t* raw = stbi_load_from_memory(
            reinterpret_cast<const stbi_uc*>(et->pcData),
            (int)et->mWidth, &w, &h, &ch, 4);
        if (!raw) return EncodeFallbackWhite(allocator, logger, out_data);

        auto res = CopyToAllocator(raw, w, h, allocator, out_data);
        stbi_image_free(raw); // matched with stbi_load_from_memory
        return res;
    }

    // Raw ARGB8888 in assimp's buffer — write directly into the destination allocator,
    // no intermediate copy needed.
    int w = (int)et->mWidth, h = (int)et->mHeight;
    size_t byte_count = (size_t)w * h * 4;
    out_data->pixels = (uint8_t*)ke_alloc(allocator, byte_count);
    if (!out_data->pixels) return KE_ERROR;

    const aiTexel* src = et->pcData;
    for (int px = 0; px < w * h; ++px)
    {
        out_data->pixels[px * 4 + 0] = src[px].r;
        out_data->pixels[px * 4 + 1] = src[px].g;
        out_data->pixels[px * 4 + 2] = src[px].b;
        out_data->pixels[px * 4 + 3] = src[px].a;
    }
    out_data->width  = (uint32_t)w;
    out_data->height = (uint32_t)h;
    return KE_OK;
}

} // namespace kernel_engine::asset::assimp::TextureDecoder
