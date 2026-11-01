#include <stddef.h>
#include <kernel_engine/render/cluster/cluster_create.h>
#include <kernel_engine/render/cluster/render_cluster_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_cluster_params),
    offsetof(ke_render_cluster_params, runtime),
    offsetof(ke_render_cluster_params, service),
    offsetof(ke_render_cluster_params, device),
    offsetof(ke_render_cluster_params, view_space),
    offsetof(ke_render_cluster_params, camera),
    offsetof(ke_render_cluster_params, scene),
    offsetof(ke_render_cluster_params, frame),
    offsetof(ke_render_cluster_params, output),
    offsetof(ke_render_cluster_params, grid_x),
    offsetof(ke_render_cluster_params, grid_y),
    offsetof(ke_render_cluster_params, grid_z),
    offsetof(ke_render_cluster_params, max_lights_per_cluster),
    offsetof(ke_render_cluster_params, configuration),
    sizeof(ke_render_cluster_handle),
    offsetof(ke_render_cluster_handle, ref),
    offsetof(ke_render_cluster_handle, destroy),
    0,
};
