#include <stddef.h>
#include <kernel_engine/render/binder_grouped/render_binder_grouped_log.h>
#include <kernel_engine/render/binder_grouped/resource_binder_grouped_create.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_resource_binder_grouped_params),
    offsetof(ke_render_resource_binder_grouped_params, device),
    offsetof(ke_render_resource_binder_grouped_params, shader_dir),
    offsetof(ke_render_resource_binder_grouped_params, io),
    0,
};
