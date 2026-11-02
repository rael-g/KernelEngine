#include <stddef.h>
#include <kernel_engine/render/tonemap/render_tonemap_log.h>
#include <kernel_engine/render/tonemap/tonemap_create.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_tonemap_params),
    offsetof(ke_render_tonemap_params, runtime),
    offsetof(ke_render_tonemap_params, service),
    offsetof(ke_render_tonemap_params, device),
    offsetof(ke_render_tonemap_params, frame),
    sizeof(ke_render_tonemap_handle),
    offsetof(ke_render_tonemap_handle, ref),
    offsetof(ke_render_tonemap_handle, destroy),
    0,
};
