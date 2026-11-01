#include <stddef.h>
#include <kernel_engine/render/shadow/render_shadow_log.h>
#include <kernel_engine/render/shadow/shadow_create.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_shadow_params),
    offsetof(ke_render_shadow_params, runtime),
    offsetof(ke_render_shadow_params, service),
    offsetof(ke_render_shadow_params, device),
    offsetof(ke_render_shadow_params, view_space),
    offsetof(ke_render_shadow_params, ndc),
    offsetof(ke_render_shadow_params, mesh_cid),
    offsetof(ke_render_shadow_params, world_transform_cid),
    offsetof(ke_render_shadow_params, light_cid),
    offsetof(ke_render_shadow_params, frame_cid),
    offsetof(ke_render_shadow_params, output),
    offsetof(ke_render_shadow_params, resolution),
    offsetof(ke_render_shadow_params, light_distance),
    offsetof(ke_render_shadow_params, extent),
    offsetof(ke_render_shadow_params, near_plane),
    offsetof(ke_render_shadow_params, far_plane),
    sizeof(ke_render_shadow_handle),
    offsetof(ke_render_shadow_handle, ref),
    offsetof(ke_render_shadow_handle, destroy),
    0,
};
