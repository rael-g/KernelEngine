#ifndef KERNEL_ENGINE_KERNEL_ENGINE_FRAME_PACKET_H_
#define KERNEL_ENGINE_KERNEL_ENGINE_FRAME_PACKET_H_

#include <kernel_engine/kernel/common/math.h>
#include <kernel_engine/kernel/render/light.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief One mesh draw call recorded by the sim thread, consumed by the render thread.
    typedef struct ke_draw_command
    {
        uint32_t mesh_handle;
        uint32_t material_handle;
        ke_mat4  transform;
    } ke_draw_command;

    /// @brief Camera state snapshot recorded once per frame.
    typedef struct ke_frame_camera
    {
        ke_mat4 view;
        ke_mat4 proj;
        float   pos_x, pos_y, pos_z;
    } ke_frame_camera;

    /// @brief Shadow pass data recorded by ShadowRenderSystem.
    typedef struct ke_frame_shadow
    {
        uint32_t map_handle; ///< UINT32_MAX = no shadow this frame
        ke_mat4  light_view;
        ke_mat4  light_proj;
    } ke_frame_shadow;

    /// @brief Immutable snapshot of all render data for one frame.
    ///        Written by the sim thread, read by the render thread.
    ///        Memory for the dynamic arrays is owned by ke_frame_sync.
    typedef struct ke_frame_packet
    {
        uint64_t frame_number;

        // ── Camera ─────────────────────────────────────────────────────────────
        ke_frame_camera camera;

        // ── Directional light ──────────────────────────────────────────────────
        ke_directional_light dir_light;
        bool                 has_dir_light;

        // ── Point lights ───────────────────────────────────────────────────────
        ke_point_light *point_lights;
        uint32_t        point_light_count;
        uint32_t        point_light_capacity;

        // ── Spot lights ────────────────────────────────────────────────────────
        ke_spot_light *spot_lights;
        uint32_t       spot_light_count;
        uint32_t       spot_light_capacity;

        // ── Draw commands ──────────────────────────────────────────────────────
        ke_draw_command *draw_commands;
        uint32_t         draw_count;
        uint32_t         draw_capacity;

        // ── Skybox ─────────────────────────────────────────────────────────────
        uint32_t skybox_handle; ///< UINT32_MAX = no skybox
        bool     has_skybox;

        // ── Shadows ────────────────────────────────────────────────────────────
        ke_frame_shadow shadow;
    } ke_frame_packet;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_ENGINE_FRAME_PACKET_H_
