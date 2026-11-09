#include <stddef.h>
#include <kernel_engine/render/skybox/render_skybox_log.h>
#include <kernel_engine/render/skybox/skybox_create.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_skybox_handle),
    offsetof(ke_render_skybox_handle, ref),
    offsetof(ke_render_skybox_handle, destroy),
    0,
};
