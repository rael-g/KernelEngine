#include <stddef.h>
#include <kernel_engine/render/skybox/render_skybox_log.h>
#include <kernel_engine/render/skybox/skybox_create.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_skybox_params),
    offsetof(ke_render_skybox_params, runtime),
    offsetof(ke_render_skybox_params, service),
    offsetof(ke_render_skybox_params, device),
    offsetof(ke_render_skybox_params, camera),
    offsetof(ke_render_skybox_params, scene),
    offsetof(ke_render_skybox_params, frame),
    sizeof(ke_render_skybox_handle),
    offsetof(ke_render_skybox_handle, ref),
    offsetof(ke_render_skybox_handle, destroy),
    0,
};
