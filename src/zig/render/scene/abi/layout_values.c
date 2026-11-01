#include <stddef.h>
#include <kernel_engine/render/scene/label_resolve_create.h>
#include <kernel_engine/render/scene/render_scene_log.h>
#include <kernel_engine/render/scene/scene_components.h>
#include <kernel_engine/render/scene/scene_resolve_create.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_label_resolve_params),
    offsetof(ke_render_label_resolve_params, runtime),
    offsetof(ke_render_label_resolve_params, service),
    offsetof(ke_render_label_resolve_params, ui),
    offsetof(ke_render_label_resolve_params, resolver),
    offsetof(ke_render_label_resolve_params, label_cid),
    sizeof(ke_render_scene_component_ids),
    offsetof(ke_render_scene_component_ids, mesh),
    offsetof(ke_render_scene_component_ids, camera),
    offsetof(ke_render_scene_component_ids, directional_light),
    offsetof(ke_render_scene_component_ids, point_light),
    offsetof(ke_render_scene_component_ids, spot_light),
    offsetof(ke_render_scene_component_ids, ambient_light),
    offsetof(ke_render_scene_component_ids, skybox),
    offsetof(ke_render_scene_component_ids, sprite2d),
    offsetof(ke_render_scene_component_ids, label),
    offsetof(ke_render_scene_component_ids, world_transform),
    sizeof(ke_render_scene_resolve_params),
    offsetof(ke_render_scene_resolve_params, runtime),
    offsetof(ke_render_scene_resolve_params, ecs),
    offsetof(ke_render_scene_resolve_params, service),
    offsetof(ke_render_scene_resolve_params, resolver),
    sizeof(ke_render_label_resolve_handle),
    offsetof(ke_render_label_resolve_handle, ref),
    offsetof(ke_render_label_resolve_handle, destroy),
    sizeof(ke_render_scene_resolve),
    offsetof(ke_render_scene_resolve, handle),
    offsetof(ke_render_scene_resolve, component_ids),
    sizeof(ke_render_scene_resolve_handle),
    offsetof(ke_render_scene_resolve_handle, ref),
    offsetof(ke_render_scene_resolve_handle, destroy),
    0,
};
