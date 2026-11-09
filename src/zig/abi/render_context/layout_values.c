#include <stddef.h>
#include <kernel_engine/render/context.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_context),
    offsetof(ke_render_context, runtime),
    offsetof(ke_render_context, ecs),
    offsetof(ke_render_context, service),
    offsetof(ke_render_context, device),
    offsetof(ke_render_context, view_space),
    offsetof(ke_render_context, camera),
    offsetof(ke_render_context, scene),
    offsetof(ke_render_context, frame),
    0,
};
