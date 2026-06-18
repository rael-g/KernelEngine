#include <kernel_engine/text/stb_truetype/stb_font.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/common/export.h>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/logger/logger.h>
#include <kernel_engine/text/font.h>

#define STB_TRUETYPE_IMPLEMENTATION
#include <stb_truetype.h>

#include <cstdio>
#include <cstring>
#include <new>
#include <vector>

namespace
{

struct StbFontLoader
{
    ke_font_loader  api{};
    ke_logger      *logger    = nullptr;
};

void destroy_loader(struct ke_font_loader *self)
{
    auto *l = reinterpret_cast<StbFontLoader *>(self);
    if (!l) return;
    l->~StbFontLoader();
    ke_free(l);
}

void free_font(struct ke_font_loader *self, ke_font_data *data)
{
    (void)self;
    if (!data) return;
    if (data->atlas_rgba) ke_free(data->atlas_rgba);
    if (data->glyphs)     ke_free(data->glyphs);
    ke_free(data);
}

ke_result load_font(struct ke_font_loader *self,
                    const char *path,
                    float pixel_size,
                    uint32_t first_codepoint,
                    uint32_t codepoint_count,
                    uint32_t atlas_size,
                    ke_font_data **out,
                    ke_error **out_error)
{
    auto *l = reinterpret_cast<StbFontLoader *>(self);
    if (!l || !path || !out) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    if (pixel_size <= 0.0f || atlas_size == 0 || codepoint_count == 0) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid font parameters");

    // 1. Slurp the TTF.
    std::FILE *fp = nullptr;
#if defined(_WIN32)
    fopen_s(&fp, path, "rb");
#else
    fp = std::fopen(path, "rb");
#endif
    if (!fp) return KE_ERROR_SET(out_error, &KE_ERROR_IO, "failed to open font file");
    std::fseek(fp, 0, SEEK_END);
    long ttf_size = std::ftell(fp);
    std::fseek(fp, 0, SEEK_SET);
    if (ttf_size <= 0) { std::fclose(fp); return KE_ERROR_SET(out_error, &KE_ERROR_IO, "empty font file"); }
    std::vector<uint8_t> ttf((size_t)ttf_size);
    size_t read = std::fread(ttf.data(), 1, (size_t)ttf_size, fp);
    std::fclose(fp);
    if (read != (size_t)ttf_size) return KE_ERROR_SET(out_error, &KE_ERROR_IO, "failed to read font file");

    // 2. Pack the requested codepoint range into a grayscale alpha atlas.
    const uint32_t W = atlas_size;
    const uint32_t H = atlas_size;
    std::vector<uint8_t> alpha((size_t)W * H, 0);

    stbtt_pack_context pc;
    if (!stbtt_PackBegin(&pc, alpha.data(), (int)W, (int)H, /*stride*/0, /*padding*/1, /*alloc_context*/nullptr))
        return KE_ERROR_SET(out_error, &KE_ERROR_GENERAL, "stbtt_PackBegin failed");
    stbtt_PackSetOversampling(&pc, 1, 1);

    std::vector<stbtt_packedchar> chars(codepoint_count);
    if (!stbtt_PackFontRange(&pc, ttf.data(), /*font_index*/0, pixel_size,
                             (int)first_codepoint, (int)codepoint_count, chars.data()))
    {
        stbtt_PackEnd(&pc);
        return KE_ERROR_SET(out_error, &KE_ERROR_GENERAL, "stbtt_PackFontRange failed");
    }
    stbtt_PackEnd(&pc);

    // 3. Expand alpha â†’ RGBA8 (white RGB + glyph-coverage alpha).
    uint8_t *atlas_rgba = (uint8_t *)ke_alloc((size_t)W * H * 4, 4);
    if (!atlas_rgba) return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "atlas allocation failed");
    for (size_t i = 0; i < (size_t)W * H; ++i)
    {
        atlas_rgba[i * 4 + 0] = 0xFF;
        atlas_rgba[i * 4 + 1] = 0xFF;
        atlas_rgba[i * 4 + 2] = 0xFF;
        atlas_rgba[i * 4 + 3] = alpha[i];
    }

    // 4. Glyph metrics + line-height from the unscaled font's v-metrics scaled to pixel_size.
    stbtt_fontinfo info;
    if (!stbtt_InitFont(&info, ttf.data(), stbtt_GetFontOffsetForIndex(ttf.data(), 0)))
    {
        ke_free(atlas_rgba);
        return KE_ERROR_SET(out_error, &KE_ERROR_GENERAL, "stbtt_InitFont failed");
    }
    int ascent_i, descent_i, line_gap_i;
    stbtt_GetFontVMetrics(&info, &ascent_i, &descent_i, &line_gap_i);
    const float scale  = stbtt_ScaleForPixelHeight(&info, pixel_size);
    const float ascent = (float)ascent_i * scale;
    const float line_h = (float)(ascent_i - descent_i + line_gap_i) * scale;

    ke_glyph_metrics *glyphs = (ke_glyph_metrics *)ke_alloc(
        sizeof(ke_glyph_metrics) * codepoint_count, alignof(ke_glyph_metrics));
    if (!glyphs) { ke_free(atlas_rgba); return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "glyphs allocation failed"); }

    for (uint32_t i = 0; i < codepoint_count; ++i)
    {
        const stbtt_packedchar &pc = chars[i];
        glyphs[i].codepoint = first_codepoint + i;
        glyphs[i].u0 = (float)pc.x0 / (float)W;
        glyphs[i].v0 = (float)pc.y0 / (float)H;
        glyphs[i].u1 = (float)pc.x1 / (float)W;
        glyphs[i].v1 = (float)pc.y1 / (float)H;
        glyphs[i].width     = (float)(pc.x1 - pc.x0);
        glyphs[i].height    = (float)(pc.y1 - pc.y0);
        glyphs[i].bearing_x = pc.xoff;
        glyphs[i].bearing_y = -pc.yoff;  // stb yoff is +down from top of glyph; we want +up from baseline
        glyphs[i].advance_x = pc.xadvance;
    }

    // 5. Assemble ke_font_data.
    ke_font_data *fd = (ke_font_data *)ke_alloc(sizeof(ke_font_data), alignof(ke_font_data));
    if (!fd) { ke_free(atlas_rgba); ke_free(glyphs); return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "font_data allocation failed"); }
    fd->atlas_rgba   = atlas_rgba;
    fd->atlas_width  = W;
    fd->atlas_height = H;
    fd->glyphs       = glyphs;
    fd->glyph_count  = codepoint_count;
    fd->line_height  = line_h;
    fd->ascent       = ascent;

    *out = fd;
    return KE_OK;
}

} // namespace

extern "C"
ke_result ke_font_loader_stb_create(const ke_font_loader_stb_params *params, ke_font_loader_handle *out, ke_error **out_error)
{
    if (!params || !out) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");

    void *mem = ke_alloc(sizeof(StbFontLoader), alignof(StbFontLoader));
    if (!mem) return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "loader allocation failed");

    auto *l = new (mem) StbFontLoader();
    l->logger    = params->logger;

    l->api.handle    = l;
    l->api.load_font = load_font;
    l->api.free_font = free_font;

    out->ref     = &l->api;
    out->destroy = destroy_loader;
    return KE_OK;
}
