#ifndef KERNEL_ENGINE_KERNEL_ENGINE_FRAME_PACKET_H_
#define KERNEL_ENGINE_KERNEL_ENGINE_FRAME_PACKET_H_

#include <kernel_engine/kernel/common/math.h>
#include <kernel_engine/kernel/common/handles.h>
#include <kernel_engine/kernel/render/light.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

    // ── Draw Commands ─────────────────────────────────────────────────────────

    typedef struct ke_draw_command {
        ke_mesh_handle     mesh_handle;
        ke_material_handle material_handle;
        ke_mat4            transform;
    } ke_draw_command;

    // ── Camera Snapshot ───────────────────────────────────────────────────────

    typedef struct ke_frame_camera {
        ke_mat4  view;
        ke_mat4  proj;
        float    pos_x, pos_y, pos_z;
    } ke_frame_camera;

    // ── Shadow Snapshot ───────────────────────────────────────────────────────

    typedef struct ke_frame_shadow {
        ke_shadow_map_handle map_handle;
        ke_mat4              light_view;
        ke_mat4              light_proj;
    } ke_frame_shadow;

    // ── Frame Packet ──────────────────────────────────────────────────────────

    typedef struct ke_frame_packet {
        uint64_t frame_number;

        // ── Scene Pass ────────────────────────────────────────────────────────
        ke_draw_command* draw_commands;
        uint32_t         draw_count;
        uint32_t         draw_capacity;

        // ── Global State ──────────────────────────────────────────────────────
        float    clear_color[4];
        float    ambient_light[3];
        ke_shadow_map_handle active_shadow_map;

        // ── Shadow Pass ───────────────────────────────────────────────────────
        ke_frame_shadow  shadow;
        ke_draw_command* shadow_draw_commands;
        uint32_t         shadow_draw_count;
        uint32_t         shadow_draw_capacity;

        // ── Lighting ──────────────────────────────────────────────────────────
        ke_directional_light dir_light;
        bool                 has_dir_light;

        ke_point_light* point_lights;
        uint32_t        point_light_count;
        uint32_t        point_light_capacity;

        ke_spot_light*  spot_lights;
        uint32_t        spot_light_count;
        uint32_t        spot_light_capacity;

        // ── Camera ────────────────────────────────────────────────────────────
        ke_frame_camera camera;

        // ── Skybox ────────────────────────────────────────────────────────────
        ke_texture_handle skybox_handle;
        bool              has_skybox;

        // ── Post-Processing & Pipeline ────────────────────────────────────────
        bool  ssao_enabled;
        float ssao_radius;
        float ssao_bias;
        float ssao_strength;

        bool  tonemapping_enabled;
        float exposure;
        float gamma;

        bool  bloom_enabled;
        float bloom_threshold;
        float bloom_intensity;

    } ke_frame_packet;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_ENGINE_FRAME_PACKET_H_
