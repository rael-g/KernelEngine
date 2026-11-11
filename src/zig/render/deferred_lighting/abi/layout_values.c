#include <stddef.h>
#include <kernel_engine/render/deferred_lighting/deferred_lighting_create.h>
#include <kernel_engine/render/deferred_lighting/render_deferred_lighting_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_deferred_lighting_config),
    offsetof(ke_render_deferred_lighting_config, ibl_enabled),
    sizeof(ke_render_deferred_lighting_handle),
    offsetof(ke_render_deferred_lighting_handle, ref),
    offsetof(ke_render_deferred_lighting_handle, destroy),
    0,
};
