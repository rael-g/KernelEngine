#include <stddef.h>
#include <kernel_engine/render/deferred_lighting/deferred_lighting_create.h>
#include <kernel_engine/render/deferred_lighting/render_deferred_lighting_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_deferred_lighting_params),
    offsetof(ke_render_deferred_lighting_params, runtime),
    offsetof(ke_render_deferred_lighting_params, service),
    offsetof(ke_render_deferred_lighting_params, device),
    offsetof(ke_render_deferred_lighting_params, ibl_enabled),
    offsetof(ke_render_deferred_lighting_params, scene),
    offsetof(ke_render_deferred_lighting_params, frame),
    offsetof(ke_render_deferred_lighting_params, gbuffer),
    offsetof(ke_render_deferred_lighting_params, shadow),
    offsetof(ke_render_deferred_lighting_params, clusters),
    sizeof(ke_render_deferred_lighting_handle),
    offsetof(ke_render_deferred_lighting_handle, ref),
    offsetof(ke_render_deferred_lighting_handle, destroy),
    0,
};
