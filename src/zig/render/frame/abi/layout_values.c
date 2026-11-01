#include <stddef.h>
#include <kernel_engine/render/frame/frame_create.h>
#include <kernel_engine/render/frame/render_frame_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_frame_params),
    offsetof(ke_render_frame_params, runtime),
    offsetof(ke_render_frame_params, ecs),
    offsetof(ke_render_frame_params, service),
    offsetof(ke_render_frame_params, camera),
    offsetof(ke_render_frame_params, camera_cid),
    offsetof(ke_render_frame_params, world_transform_cid),
    offsetof(ke_render_frame_params, directional_light_cid),
    offsetof(ke_render_frame_params, ambient_light_cid),
    0,
};
