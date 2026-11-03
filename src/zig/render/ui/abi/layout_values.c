#include <stddef.h>
#include <kernel_engine/render/ui/render_ui_log.h>
#include <kernel_engine/render/ui/ui_create.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_ui_params),
    offsetof(ke_render_ui_params, runtime),
    offsetof(ke_render_ui_params, ecs),
    offsetof(ke_render_ui_params, service),
    offsetof(ke_render_ui_params, device),
    offsetof(ke_render_ui_params, frame),
    0,
};
