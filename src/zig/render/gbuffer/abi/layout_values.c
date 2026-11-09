#include <stddef.h>
#include <kernel_engine/render/gbuffer/gbuffer_create.h>
#include <kernel_engine/render/gbuffer/render_gbuffer_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_gbuffer_handle),
    offsetof(ke_render_gbuffer_handle, ref),
    offsetof(ke_render_gbuffer_handle, destroy),
    0,
};
