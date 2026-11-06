#include <stddef.h>
#include <kernel_engine/render/service/render_service_create.h>
#include <kernel_engine/render/service/render_service_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_service_config),
    offsetof(ke_render_service_config, shader_dir),
    offsetof(ke_render_service_config, color_format),
    offsetof(ke_render_service_config, depth_format),
    offsetof(ke_render_service_config, clear_color),
    0,
};
