#ifndef KERNEL_ENGINE_RENDER_FRAME_PACKET_H_
#define KERNEL_ENGINE_RENDER_FRAME_PACKET_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/common/math.h>
#include <kernel_engine/render/handles.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/render/light.h>
#include <kernel_engine/common/types.h>
#include <stdint.h>

#ifndef KE_FRAME_PACKET_API
#  ifdef KE_RENDER_STATIC
#    define KE_FRAME_PACKET_API
#  elif defined(KE_RENDER_EXPORT)
#    define KE_FRAME_PACKET_API KE_EXPORT
#  else
#    define KE_FRAME_PACKET_API KE_IMPORT
#  endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

    typedef struct ke_draw_command {
        ke_mesh_handle     mesh_handle;
        ke_material_handle material_handle;
        ke_mat4            transform;
    } ke_draw_command;

    typedef struct ke_ui_draw_command {
        ke_texture_handle texture;
        float             dst_x, dst_y;
        float             dst_w, dst_h;
        float             src_u0, src_v0;
        float             src_u1, src_v1;
        float             color[4];
    } ke_ui_draw_command;

    typedef struct ke_frame_camera {
        ke_mat4 view;
        ke_mat4 proj;
        float   pos_x, pos_y, pos_z;
    } ke_frame_camera;

    typedef struct ke_frame_shadow {
        ke_shadow_map_handle map_handle;
        ke_mat4              light_view;
        ke_mat4              light_proj;
    } ke_frame_shadow;

    typedef struct ke_frame_packet {
        uint64_t frame_number;

        ke_draw_command *draw_commands;
        uint32_t         draw_count;
        uint32_t         draw_capacity;

        float                clear_color[4];
        float                ambient_light[3];
        ke_shadow_map_handle active_shadow_map;

        ke_frame_shadow  shadow;
        ke_draw_command *shadow_draw_commands;
        uint32_t         shadow_draw_count;
        uint32_t         shadow_draw_capacity;

        ke_directional_light dir_light;
        ke_bool              has_dir_light;

        ke_point_light  *point_lights;
        uint32_t         point_light_count;
        uint32_t         point_light_capacity;

        ke_spot_light   *spot_lights;
        uint32_t         spot_light_count;
        uint32_t         spot_light_capacity;

        ke_frame_camera camera;

        ke_texture_handle skybox_handle;
        ke_bool           has_skybox;

        ke_bool ssao_enabled;
        float   ssao_radius;
        float   ssao_bias;
        float   ssao_strength;

        ke_bool tonemapping_enabled;
        float   exposure;
        float   gamma;

        ke_bool bloom_enabled;
        float bloom_threshold;
        float bloom_intensity;

        ke_ui_draw_command *ui_draw_commands;
        uint32_t            ui_draw_count;
        uint32_t            ui_draw_capacity;

    } ke_frame_packet;

    typedef struct ke_frame_packet_params {
        uint32_t draw_capacity;
        uint32_t shadow_draw_capacity;
        uint32_t point_light_capacity;
        uint32_t spot_light_capacity;
        uint32_t ui_draw_capacity;
    } ke_frame_packet_params;

    KE_FRAME_PACKET_API bool ke_frame_packet_create(const ke_frame_packet_params *params,
                                                     ke_frame_packet **out_packet,
                                                     ke_error **out_error);
    KE_FRAME_PACKET_API void ke_frame_packet_destroy(ke_frame_packet *packet);
    KE_FRAME_PACKET_API void ke_frame_packet_reset(ke_frame_packet *packet);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_FRAME_PACKET_H_
