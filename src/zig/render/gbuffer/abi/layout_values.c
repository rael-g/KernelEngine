#include <stddef.h>
#include <kernel_engine/render/gbuffer/gbuffer_create.h>
#include <kernel_engine/render/gbuffer/render_gbuffer_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_gbuffer_params),
    offsetof(ke_render_gbuffer_params, runtime),
    offsetof(ke_render_gbuffer_params, service),
    offsetof(ke_render_gbuffer_params, device),
    offsetof(ke_render_gbuffer_params, mesh_cid),
    offsetof(ke_render_gbuffer_params, world_transform_cid),
    offsetof(ke_render_gbuffer_params, camera_cid),
    offsetof(ke_render_gbuffer_params, frame_cid),
    offsetof(ke_render_gbuffer_params, output),
    sizeof(ke_render_gbuffer_handle),
    offsetof(ke_render_gbuffer_handle, ref),
    offsetof(ke_render_gbuffer_handle, destroy),
    0,
};
