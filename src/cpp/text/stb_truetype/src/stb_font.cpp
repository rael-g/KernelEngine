#include <kernel_engine/text/stb_truetype/stb_font.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/types.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/text/font.h>

#define STB_TRUETYPE_IMPLEMENTATION
#include <stb_truetype.h>

#include <cstdio>
#include <cstring>
#include <vector>

namespace
{

struct StbFont
{
    ke_font           api{};                  // Must be first (we cast self → StbFont*)
    ke_allocator     *allocator = nullptr;
    ke_logger        *logger    = nullptr;
    ke_texture_handle atlas     = KE_TEXTURE_NONE;
    ke_render        *render    = nullptr;
    uint32_t          first_cp  = 32;
    uint32_t          cp_count  = 95;
    float             line_h    = 0.0f;
    std::vector<stbtt_packedchar> chars;      // one per codepoint
    uint16_t          atlas_size = 512;
};

// ── vtable implementations ──────────────────────────────────────────────────

void destroy(struct ke_font *self)
{
    auto *f = reinterpret_cast<StbFont *>(self);
    if (!f) return;
    if (f->render && ke_texture_is_valid(f->atlas))
        f->render->destroy_texture(f->render, f->atlas);
    auto *alloc = f->allocator;
    f->~StbFont();
    if (alloc) alloc->free(alloc, f);
}

ke_bool glyph(struct ke_font *self, uint32_t codepoint, ke_glyph_metrics *out)
{
    auto *f = reinterpret_cast<StbFont *>(self);
    if (!f || !out) return 0;
    if (codepoint < f->first_cp || codepoint >= f->first_cp + f->cp_count) return 0;

    const stbtt_packedchar &pc = f->chars[codepoint - f->first_cp];

    out->u0 = (float)pc.x0 / (float)f->atlas_size;
    out->v0 = (float)pc.y0 / (float)f->atlas_size;
    out->u1 = (float)pc.x1 / (float)f->atlas_size;
    out->v1 = (float)pc.y1 / (float)f->atlas_size;

    out->width     = (float)(pc.x1 - pc.x0);
    out->height    = (float)(pc.y1 - pc.y0);
    out->bearing_x = pc.xoff;
    out->bearing_y = -pc.yoff;        // stb yoff is +down from baseline; we want +up to top of glyph
    out->advance_x = pc.xadvance;

    return 1;
}

ke_texture_handle atlas_texture(struct ke_font *self)
{
    auto *f = reinterpret_cast<StbFont *>(self);
    return f ? f->atlas : KE_TEXTURE_NONE;
}

float line_height(struct ke_font *self)
{
    auto *f = reinterpret_cast<StbFont *>(self);
    return f ? f->line_h : 0.0f;
}

} // namespace

extern "C"
ke_result ke_font_stb_create(const ke_font_stb_params *params, ke_font **out)
{
    if (!params || !out || !params->allocator || !params->render || !params->ttf_path)
        return KE_ERROR_INVALID_ARGUMENT;
    if (params->pixel_size <= 0.0f || params->atlas_size == 0 || params->codepoint_count == 0)
        return KE_ERROR_INVALID_ARGUMENT;

    auto *alloc = params->allocator;

    // 1. Slurp the TTF file.
    std::FILE *fp = nullptr;
#if defined(_WIN32)
    fopen_s(&fp, params->ttf_path, "rb");
#else
    fp = std::fopen(params->ttf_path, "rb");
#endif
    if (!fp) return KE_ERROR_IO;
    std::fseek(fp, 0, SEEK_END);
    long ttf_size = std::ftell(fp);
    std::fseek(fp, 0, SEEK_SET);
    if (ttf_size <= 0) { std::fclose(fp); return KE_ERROR_IO; }
    std::vector<uint8_t> ttf((size_t)ttf_size);
    size_t read = std::fread(ttf.data(), 1, (size_t)ttf_size, fp);
    std::fclose(fp);
    if (read != (size_t)ttf_size) return KE_ERROR_IO;

    // 2. Bake the requested codepoint range into a grayscale alpha atlas.
    const uint16_t W = params->atlas_size;
    const uint16_t H = params->atlas_size;
    std::vector<uint8_t> alpha((size_t)W * H, 0);

    stbtt_pack_context pc;
    if (!stbtt_PackBegin(&pc, alpha.data(), W, H, /*stride*/0, /*padding*/1, /*alloc_context*/nullptr))
        return KE_ERROR_RENDER;
    stbtt_PackSetOversampling(&pc, 1, 1);

    std::vector<stbtt_packedchar> chars(params->codepoint_count);
    if (!stbtt_PackFontRange(&pc, ttf.data(), /*font_index*/0, params->pixel_size,
                             (int)params->first_codepoint, (int)params->codepoint_count, chars.data()))
    {
        stbtt_PackEnd(&pc);
        return KE_ERROR_RENDER;
    }
    stbtt_PackEnd(&pc);

    // 3. Expand the alpha-only atlas into RGBA8 (white RGB, alpha from glyph coverage) so it
    // works with the existing create_texture_rgba path and the UI shader (which multiplies
    // by vertex tint — text gets its color from the vertex, not the atlas).
    std::vector<uint8_t> rgba((size_t)W * H * 4);
    for (size_t i = 0; i < (size_t)W * H; ++i)
    {
        rgba[i * 4 + 0] = 0xFF;
        rgba[i * 4 + 1] = 0xFF;
        rgba[i * 4 + 2] = 0xFF;
        rgba[i * 4 + 3] = alpha[i];
    }

    // 4. Upload as the atlas texture (render-thread call).
    ke_texture_handle tex = KE_TEXTURE_NONE;
    if (params->render->create_texture_rgba(params->render, W, H, rgba.data(), &tex) != KE_OK)
        return KE_ERROR_RENDER;

    // 5. Compute line height from the unscaled font's v-metrics scaled to our pixel size.
    stbtt_fontinfo info;
    if (!stbtt_InitFont(&info, ttf.data(), stbtt_GetFontOffsetForIndex(ttf.data(), 0)))
    {
        params->render->destroy_texture(params->render, tex);
        return KE_ERROR_RENDER;
    }
    int ascent, descent, line_gap;
    stbtt_GetFontVMetrics(&info, &ascent, &descent, &line_gap);
    const float scale  = stbtt_ScaleForPixelHeight(&info, params->pixel_size);
    const float line_h = (float)(ascent - descent + line_gap) * scale;

    // 6. Allocate the StbFont struct + wire the vtable.
    void *mem = alloc->alloc(alloc, sizeof(StbFont), alignof(StbFont));
    if (!mem) { params->render->destroy_texture(params->render, tex); return KE_ERROR_OUT_OF_MEMORY; }
    auto *f = new (mem) StbFont();
    f->allocator   = alloc;
    f->logger      = params->logger;
    f->render      = params->render;
    f->atlas       = tex;
    f->atlas_size  = W;
    f->first_cp    = params->first_codepoint;
    f->cp_count    = params->codepoint_count;
    f->line_h      = line_h;
    f->chars       = std::move(chars);

    f->api.handle        = f;
    f->api.destroy       = destroy;
    f->api.glyph         = glyph;
    f->api.atlas_texture = atlas_texture;
    f->api.line_height   = line_height;

    *out = &f->api;
    return KE_OK;
}
