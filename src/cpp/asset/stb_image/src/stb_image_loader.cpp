// stb_image is header-only. We're a separate shared library from the assimp plugin (which also
// pulls stb in), so each DLL gets its own internal copy of the implementation — no collision.
#define STB_IMAGE_IMPLEMENTATION
#include <stb_image.h>

#include "kernel_engine/asset/stb_image/stb_image_loader.h"
#include "kernel_engine/common/error.h"
#include "kernel_engine/allocator/allocator.h"
#include "kernel_engine/logger/logger.h"

#include <cstring>
#include <cstdlib>

namespace {

struct StbImageLoaderState
{
    ke_allocator *allocator;
    ke_logger    *logger;
};

void log_warn(ke_logger *logger, const char *msg)
{
    if (!logger) return;
    ke_log_event ev{ KE_LOG_LEVEL_WARNING, "stb_image", msg };
    logger->log(logger, &ev);
}

void destroy(ke_image_loader *self)
{
    if (!self) return;
    auto *state = static_cast<StbImageLoaderState *>(self->handle);
    auto *alloc = state ? state->allocator : nullptr;
    if (state && alloc) alloc->free(alloc, state);
    if (alloc) alloc->free(alloc, self);
}

ke_result load_image(ke_image_loader *self, const char *path, ke_texture_data **out, ke_error **out_error)
{
    if (!self || !path || !out) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    *out = nullptr;

    auto *state = static_cast<StbImageLoaderState *>(self->handle);
    auto *alloc = state->allocator;

    int w = 0, h = 0, channels = 0;
    // Force RGBA8 — matches ke_texture_data's contract (4 bytes/pixel, row-major).
    stbi_uc *raw = stbi_load(path, &w, &h, &channels, 4);
    if (!raw) {
        log_warn(state->logger, stbi_failure_reason());
        return KE_ERROR_SET(out_error, &KE_ERROR_NOT_FOUND, "image file not found or failed to decode");
    }

    const size_t pixel_bytes = static_cast<size_t>(w) * static_cast<size_t>(h) * 4u;

    auto *data = static_cast<ke_texture_data *>(alloc->alloc(alloc, sizeof(ke_texture_data), alignof(ke_texture_data)));
    if (!data) { stbi_image_free(raw); return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "texture data allocation failed"); }
    std::memset(data, 0, sizeof(*data));

    auto *pixels = static_cast<uint8_t *>(alloc->alloc(alloc, pixel_bytes, 1));
    if (!pixels) {
        stbi_image_free(raw);
        alloc->free(alloc, data);
        return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "pixel buffer allocation failed");
    }
    std::memcpy(pixels, raw, pixel_bytes);
    stbi_image_free(raw);

    data->pixels = pixels;
    data->width  = static_cast<uint32_t>(w);
    data->height = static_cast<uint32_t>(h);
    // Copy path (truncate safely to the fixed-size field).
    const size_t n = std::strlen(path);
    const size_t cap = sizeof(data->path) - 1;
    const size_t copy = n < cap ? n : cap;
    std::memcpy(data->path, path, copy);
    data->path[copy] = '\0';

    *out = data;
    return KE_OK;
}

void free_image(ke_image_loader *self, ke_texture_data *data)
{
    if (!self || !data) return;
    auto *state = static_cast<StbImageLoaderState *>(self->handle);
    auto *alloc = state->allocator;
    if (data->pixels) alloc->free(alloc, data->pixels);
    alloc->free(alloc, data);
}

} // namespace

extern "C" KE_ASSET_STB_IMAGE_API ke_result ke_image_loader_stb_create(
    const ke_image_loader_stb_params *params,
    ke_image_loader_handle *out,
    ke_error **out_error)
{
    if (!params || !params->allocator || !out) return KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
    auto *alloc = params->allocator;

    auto *state = static_cast<StbImageLoaderState *>(alloc->alloc(alloc, sizeof(StbImageLoaderState), alignof(StbImageLoaderState)));
    if (!state) return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "state allocation failed");
    state->allocator = alloc;
    state->logger    = params->logger;

    auto *loader = static_cast<ke_image_loader *>(alloc->alloc(alloc, sizeof(ke_image_loader), alignof(ke_image_loader)));
    if (!loader) { alloc->free(alloc, state); return KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "loader allocation failed"); }
    loader->handle     = state;
    loader->load_image = &load_image;
    loader->free_image = &free_image;

    out->ref     = loader;
    out->destroy = &destroy;
    return KE_OK;
}
