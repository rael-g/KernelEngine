#pragma once

#include <kernel_engine/kernel/context/types.h>
#include <kernel_engine/kernel/render/render.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef KE_RENDER_API
    #ifdef KE_RENDER_STATIC
        #define KE_RENDER_API
    #else
        #ifdef KE_RENDER_EXPORT
            #define KE_RENDER_API KE_HELPER_EXPORT
        #else
            #define KE_RENDER_API KE_HELPER_IMPORT
        #endif
    #endif
#endif

struct ke_window;
/// @brief Parameters for BGFX render system creation.
typedef struct ke_render_bgfx_params
{
    struct ke_allocator *allocator;
    struct ke_logger *logger;
    struct ke_message_pipe *message_pipe;
    struct ke_window *window;
    const char *shader_path;
    uint32_t renderer_type; // 0 = Default (Vulkan), or bgfx::RendererType
} ke_render_bgfx_params;

/**
 * @brief Creates the BGFX render system implementation.
 */
KE_RENDER_API ke_result ke_render_bgfx_create(const ke_render_bgfx_params* params, ke_render** out_render);

#ifdef __cplusplus
}
#endif
