#include <stddef.h>
#include <kernel_engine/render/forward/forward_create.h>
#include <kernel_engine/render/forward/render_forward_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_forward_params),
    offsetof(ke_render_forward_params, runtime),
    offsetof(ke_render_forward_params, service),
    offsetof(ke_render_forward_params, device),
    offsetof(ke_render_forward_params, ibl_enabled),
    offsetof(ke_render_forward_params, mesh_cid),
    offsetof(ke_render_forward_params, world_transform_cid),
    offsetof(ke_render_forward_params, camera_cid),
    offsetof(ke_render_forward_params, skybox_cid),
    offsetof(ke_render_forward_params, frame_cid),
    offsetof(ke_render_forward_params, shadow),
    offsetof(ke_render_forward_params, clusters),
    sizeof(ke_render_forward_handle),
    offsetof(ke_render_forward_handle, ref),
    offsetof(ke_render_forward_handle, destroy),
    0,
};
