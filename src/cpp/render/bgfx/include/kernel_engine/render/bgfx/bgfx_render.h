#pragma once

#include <kernel_engine/common/export.h>
#include <kernel_engine/render/render.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef KE_RENDER_BGFX_API
    #ifdef KE_RENDER_STATIC
        #define KE_RENDER_BGFX_API
    #else
        #ifdef KE_RENDER_BGFX_EXPORT
            #define KE_RENDER_BGFX_API KE_EXPORT
        #else
            #define KE_RENDER_BGFX_API KE_IMPORT
        #endif
    #endif
#endif

struct ke_window;
/// @brief Parameters for BGFX render system creation.
typedef struct ke_render_bgfx_params
{
    struct ke_logger *logger;
    struct ke_window *window;
    const char *shader_path;
    uint32_t renderer_type; // 0 = Vulkan (engine default), or explicit bgfx::RendererType value
    bool vsync;
} ke_render_bgfx_params;

/**
 * @brief Creates the BGFX render system implementation.
 * @return Handle whose @c ref is NULL on failure.
 */
KE_RENDER_BGFX_API ke_render_handle ke_render_bgfx_create(const ke_render_bgfx_params* params, ke_error** out_error);

#ifdef __cplusplus
}
#endif
