#include <kernel_engine/render/frame_packet.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>
#include <stdalign.h>
#include <stdbool.h>
#include <string.h>

// Padding before the public ke_frame_packet for alignment purposes.
#define FP_PRIV_SIZE alignof(ke_frame_packet)

bool ke_frame_packet_create(const ke_frame_packet_params *params,
                                 ke_frame_packet **out_packet,
                                 ke_error **out_error)
{
    if (!params || !out_packet) { KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument"); return false; }

    // Allocate [padding | ke_frame_packet] in one block.
    size_t block = FP_PRIV_SIZE + sizeof(ke_frame_packet);
    void *mem = ke_alloc(block, alignof(ke_frame_packet));
    if (!mem) return false;
    memset(mem, 0, block);

    ke_frame_packet *p = (ke_frame_packet *)((char *)mem + FP_PRIV_SIZE);
    p->skybox_handle      = KE_TEXTURE_NONE;
    p->shadow.map_handle  = KE_SHADOW_MAP_NONE;
    p->active_shadow_map  = KE_SHADOW_MAP_NONE;

    if (params->draw_capacity) {
        p->draw_commands = (ke_draw_command *)ke_alloc(
            sizeof(ke_draw_command) * params->draw_capacity, 0);
        if (!p->draw_commands) goto fail;
        p->draw_capacity = params->draw_capacity;
    }
    if (params->shadow_draw_capacity) {
        p->shadow_draw_commands = (ke_draw_command *)ke_alloc(
            sizeof(ke_draw_command) * params->shadow_draw_capacity, 0);
        if (!p->shadow_draw_commands) goto fail;
        p->shadow_draw_capacity = params->shadow_draw_capacity;
    }
    if (params->point_light_capacity) {
        p->point_lights = (ke_point_light *)ke_alloc(
            sizeof(ke_point_light) * params->point_light_capacity, 0);
        if (!p->point_lights) goto fail;
        p->point_light_capacity = params->point_light_capacity;
    }
    if (params->spot_light_capacity) {
        p->spot_lights = (ke_spot_light *)ke_alloc(
            sizeof(ke_spot_light) * params->spot_light_capacity, 0);
        if (!p->spot_lights) goto fail;
        p->spot_light_capacity = params->spot_light_capacity;
    }
    if (params->ui_draw_capacity) {
        p->ui_draw_commands = (ke_ui_draw_command *)ke_alloc(
            sizeof(ke_ui_draw_command) * params->ui_draw_capacity, 0);
        if (!p->ui_draw_commands) goto fail;
        p->ui_draw_capacity = params->ui_draw_capacity;
    }

    *out_packet = p;
    return true;

fail:
    ke_frame_packet_destroy(p);
    KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "sub-buffer allocation failed");
    return false;
}

void ke_frame_packet_destroy(ke_frame_packet *packet)
{
    if (!packet) return;
    if (packet->draw_commands)        ke_free(packet->draw_commands);
    if (packet->shadow_draw_commands) ke_free(packet->shadow_draw_commands);
    if (packet->point_lights)         ke_free(packet->point_lights);
    if (packet->spot_lights)          ke_free(packet->spot_lights);
    if (packet->ui_draw_commands)     ke_free(packet->ui_draw_commands);
    // Free the entire [padding | ke_frame_packet] block via the base address.
    ke_free((char *)packet - FP_PRIV_SIZE);
}

void ke_frame_packet_reset(ke_frame_packet *p)
{
    if (!p) return;
    p->draw_count          = 0;
    p->shadow_draw_count   = 0;
    p->point_light_count   = 0;
    p->spot_light_count    = 0;
    p->ui_draw_count       = 0;
    p->has_dir_light       = false;
    p->has_skybox          = false;
    p->active_shadow_map   = KE_SHADOW_MAP_NONE;
    p->shadow.map_handle   = KE_SHADOW_MAP_NONE;
}
