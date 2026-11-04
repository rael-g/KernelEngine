#include <stddef.h>
#include <kernel_engine/render/service/render_service_create.h>
#include <kernel_engine/render/service/render_service_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_service_params),
    offsetof(ke_render_service_params, device),
    offsetof(ke_render_service_params, target),
    offsetof(ke_render_service_params, ecs),
    offsetof(ke_render_service_params, shader_dir),
    offsetof(ke_render_service_params, io),
    offsetof(ke_render_service_params, binder),
    offsetof(ke_render_service_params, color_format),
    offsetof(ke_render_service_params, depth_format),
    offsetof(ke_render_service_params, clear_color),
    offsetof(ke_render_service_params, configuration),
    0,
};
