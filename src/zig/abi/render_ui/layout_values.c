#include <stddef.h>
#include <kernel_engine/render/ui/ui.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_ui),
    offsetof(ke_render_ui, handle),
    offsetof(ke_render_ui, load_font),
    sizeof(ke_render_ui_handle),
    offsetof(ke_render_ui_handle, ref),
    offsetof(ke_render_ui_handle, destroy),
    0,
};
