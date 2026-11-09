#include <stddef.h>
#include <kernel_engine/render/shadow/render_shadow_log.h>
#include <kernel_engine/render/shadow/shadow_create.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_shadow_config),
    offsetof(ke_render_shadow_config, resolution),
    offsetof(ke_render_shadow_config, light_distance),
    offsetof(ke_render_shadow_config, extent),
    offsetof(ke_render_shadow_config, near_plane),
    offsetof(ke_render_shadow_config, far_plane),
    sizeof(ke_render_shadow_handle),
    offsetof(ke_render_shadow_handle, ref),
    offsetof(ke_render_shadow_handle, destroy),
    0,
};
