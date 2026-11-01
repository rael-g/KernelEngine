#include <stddef.h>
#include <kernel_engine/render/ui/render_ui_log.h>
#include <kernel_engine/render/ui/ui_create.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_ui_params),
    offsetof(ke_render_ui_params, runtime),
    offsetof(ke_render_ui_params, ecs),
    offsetof(ke_render_ui_params, service),
    offsetof(ke_render_ui_params, device),
    offsetof(ke_render_ui_params, ndc),
    offsetof(ke_render_ui_params, frame_cid),
    sizeof(ke_render_ui),
    offsetof(ke_render_ui, handle),
    offsetof(ke_render_ui, load_font),
    sizeof(ke_render_ui_handle),
    offsetof(ke_render_ui_handle, ref),
    offsetof(ke_render_ui_handle, destroy),
    0,
};
