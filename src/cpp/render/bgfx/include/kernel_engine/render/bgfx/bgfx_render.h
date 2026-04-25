#pragma once

#include <kernel_engine/kernel/context/types.h>
#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/world/system.h>
#include <stdint.h>

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
    uint32_t renderer_type; // 0 = Vulkan (engine default), or explicit bgfx::RendererType value
} ke_render_bgfx_params;

/**
 * @brief Creates the BGFX render system implementation.
 */
KE_RENDER_API ke_result ke_render_bgfx_create(const ke_render_bgfx_params* params, ke_render** out_render);

// ── Native System Descriptor Factories ────────────────────────────────────────

KE_RENDER_API ke_result ke_render_bgfx_create_mesh_system_desc(uint32_t mesh_cid, uint32_t transform_cid, ke_system_desc* out_desc);
KE_RENDER_API ke_result ke_render_bgfx_create_light_system_desc(uint32_t light_cid, uint32_t point_cid, uint32_t spot_cid, uint32_t transform_cid, ke_system_desc* out_desc);
KE_RENDER_API ke_result ke_render_bgfx_create_camera_system_desc(uint32_t camera_cid, uint32_t transform_cid, ke_system_desc* out_desc);
KE_RENDER_API ke_result ke_render_bgfx_create_shadow_system_desc(ke_render* renderer, uint32_t light_cid, uint32_t mesh_cid, uint32_t transform_cid, ke_system_desc* out_desc);
KE_RENDER_API ke_result ke_render_bgfx_create_skybox_system_desc(uint32_t skybox_cid, ke_system_desc* out_desc);

#ifdef __cplusplus
}
#endif
