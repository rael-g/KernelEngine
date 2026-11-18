#include <stddef.h>
#include <kernel_engine/render/forward/forward_create.h>
#include <kernel_engine/render/forward/render_forward_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_forward_config),
    offsetof(ke_render_forward_config, ibl_enabled),
    0,
};
