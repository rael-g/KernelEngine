#include <kernel_engine/render/frame_packet.h>
#include <string.h>

ke_result ke_frame_packet_create(const ke_frame_packet_params *params,
                                 ke_frame_packet **out_packet)
{
    if (!params || !params->allocator || !out_packet) return KE_ERROR_INVALID_ARGUMENT;
    ke_allocator *alloc = params->allocator;

    ke_frame_packet *p = (ke_frame_packet *)alloc->alloc(
        alloc, sizeof(ke_frame_packet), 0);
    if (!p) return KE_ERROR_OUT_OF_MEMORY;
    memset(p, 0, sizeof(ke_frame_packet));
    p->skybox_handle      = KE_TEXTURE_NONE;
    p->shadow.map_handle  = KE_SHADOW_MAP_NONE;
    p->active_shadow_map  = KE_SHADOW_MAP_NONE;

    if (params->draw_capacity) {
        p->draw_commands = (ke_draw_command *)alloc->alloc(
            alloc, sizeof(ke_draw_command) * params->draw_capacity, 0);
        if (!p->draw_commands) goto fail;
        p->draw_capacity = params->draw_capacity;
    }
    if (params->shadow_draw_capacity) {
        p->shadow_draw_commands = (ke_draw_command *)alloc->alloc(
            alloc, sizeof(ke_draw_command) * params->shadow_draw_capacity, 0);
        if (!p->shadow_draw_commands) goto fail;
        p->shadow_draw_capacity = params->shadow_draw_capacity;
    }
    if (params->point_light_capacity) {
        p->point_lights = (ke_point_light *)alloc->alloc(
            alloc, sizeof(ke_point_light) * params->point_light_capacity, 0);
        if (!p->point_lights) goto fail;
        p->point_light_capacity = params->point_light_capacity;
    }
    if (params->spot_light_capacity) {
        p->spot_lights = (ke_spot_light *)alloc->alloc(
            alloc, sizeof(ke_spot_light) * params->spot_light_capacity, 0);
        if (!p->spot_lights) goto fail;
        p->spot_light_capacity = params->spot_light_capacity;
    }
    if (params->ui_draw_capacity) {
        p->ui_draw_commands = (ke_ui_draw_command *)alloc->alloc(
            alloc, sizeof(ke_ui_draw_command) * params->ui_draw_capacity, 0);
        if (!p->ui_draw_commands) goto fail;
        p->ui_draw_capacity = params->ui_draw_capacity;
    }

    *out_packet = p;
    return KE_OK;

fail:
    ke_frame_packet_destroy(alloc, p);
    return KE_ERROR_OUT_OF_MEMORY;
}

void ke_frame_packet_destroy(ke_allocator *allocator, ke_frame_packet *packet)
{
    if (!allocator || !packet) return;
    if (packet->draw_commands)        allocator->free(allocator, packet->draw_commands);
    if (packet->shadow_draw_commands) allocator->free(allocator, packet->shadow_draw_commands);
    if (packet->point_lights)         allocator->free(allocator, packet->point_lights);
    if (packet->spot_lights)          allocator->free(allocator, packet->spot_lights);
    if (packet->ui_draw_commands)     allocator->free(allocator, packet->ui_draw_commands);
    allocator->free(allocator, packet);
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
