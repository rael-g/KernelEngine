#pragma once

#include <kernel_engine/kernel/context/types.h>
#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/world/system.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef KE_RENDER_BGFX_API
    #ifdef KE_RENDER_STATIC
        #define KE_RENDER_BGFX_API
    #else
        #ifdef KE_RENDER_BGFX_EXPORT
            #define KE_RENDER_BGFX_API KE_HELPER_EXPORT
        #else
            #define KE_RENDER_BGFX_API KE_HELPER_IMPORT
        #endif
    #endif
#endif

struct ke_window;
/// @brief Parameters for BGFX render system creation.
typedef struct ke_render_bgfx_params
{
    struct ke_allocator *allocator;
    struct ke_logger *logger;
    struct ke_window *window;
    const char *shader_path;
    uint32_t renderer_type; // 0 = Vulkan (engine default), or explicit bgfx::RendererType value
    ke_bool vsync;
} ke_render_bgfx_params;

/**
 * @brief Creates the BGFX render system implementation.
 */
KE_RENDER_BGFX_API ke_result ke_render_bgfx_create(const ke_render_bgfx_params* params, ke_render** out_render);

#ifdef __cplusplus
}
#endif
