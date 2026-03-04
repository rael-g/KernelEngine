#pragma once

#include <kernel_engine/core/engine/system.h>
#include <kernel_engine/core/common/descriptor.h>
#include <kernel_engine/core/context/types.h>

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

/// @brief Configuration for the BGFX render system.
typedef struct ke_render_bgfx_descriptor {
    struct ke_allocator* allocator;
    struct ke_logger* logger;
    struct ke_message_pipe* message_pipe;
    struct ke_window* window;
    const char* shader_path;
} ke_render_bgfx_descriptor;

/**
 * @brief Creates the BGFX render system plugin.
 */
KE_RENDER_API ke_result ke_render_bgfx_create(const ke_render_bgfx_descriptor* desc, ke_system** out_system);

#ifdef __cplusplus
}

namespace kernel_engine::render::bgfx {
    ke_result CreateBgfxRenderSystem(const ke_render_bgfx_descriptor* desc, ke_system** out_system);
}
#endif
