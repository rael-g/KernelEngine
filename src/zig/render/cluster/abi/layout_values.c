#include <stddef.h>
#include <kernel_engine/render/cluster/cluster_create.h>
#include <kernel_engine/render/cluster/render_cluster_log.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_cluster_config),
    offsetof(ke_render_cluster_config, grid_x),
    offsetof(ke_render_cluster_config, grid_y),
    offsetof(ke_render_cluster_config, grid_z),
    offsetof(ke_render_cluster_config, max_lights_per_cluster),
    sizeof(ke_render_cluster_handle),
    offsetof(ke_render_cluster_handle, ref),
    offsetof(ke_render_cluster_handle, destroy),
    0,
};
