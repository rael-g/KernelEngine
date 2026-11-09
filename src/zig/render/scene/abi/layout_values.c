#include <stddef.h>
#include <kernel_engine/render/scene/label_resolve_create.h>
#include <kernel_engine/render/scene/render_scene_log.h>
#include <kernel_engine/render/scene/scene_resolve_create.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_label_resolve_config),
    offsetof(ke_render_label_resolve_config, default_font),
    sizeof(ke_render_scene_resolve_params),
    offsetof(ke_render_scene_resolve_params, runtime),
    offsetof(ke_render_scene_resolve_params, ecs),
    offsetof(ke_render_scene_resolve_params, service),
    offsetof(ke_render_scene_resolve_params, resolver),
    sizeof(ke_render_label_resolve_handle),
    offsetof(ke_render_label_resolve_handle, ref),
    offsetof(ke_render_label_resolve_handle, destroy),
    0,
};
