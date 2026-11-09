#ifndef KERNEL_ENGINE_RENDER_RESOURCE_GROUPS_H_
#define KERNEL_ENGINE_RENDER_RESOURCE_GROUPS_H_

#include <kernel_engine/ecs/ecs.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// The resources a gbuffer pass writes, as the render service's ids. Every id
    /// KE_COMPONENT_INVALID stands for no gbuffer.
    typedef struct ke_render_gbuffer_resources
    {
        ke_component_id albedo;   ///< The base color.
        ke_component_id normal;   ///< The world normal.
        ke_component_id emissive; ///< The emitted light.
    } ke_render_gbuffer_resources;

    /// The resources a directional shadow pass writes, as the render service's ids. Every id
    /// KE_COMPONENT_INVALID stands for no shadow, which a reader meets with the neutral one.
    typedef struct ke_render_shadow_resources
    {
        ke_component_id map;   ///< The shadow map.
        ke_component_id light; ///< The buffer holding the light's view-projection.
    } ke_render_shadow_resources;

    /// The resources a light-cluster pass writes, as the render service's ids. Every id
    /// KE_COMPONENT_INVALID stands for no clustered light.
    typedef struct ke_render_cluster_resources
    {
        ke_component_id tag;           ///< The tag the pass writes, which orders its readers after it.
        ke_component_id point_lights;  ///< The clustered point lights.
        ke_component_id spot_lights;   ///< The clustered spot lights.
        ke_component_id point_indices; ///< The point light indices of each cluster.
        ke_component_id point_counts;  ///< The point light count of each cluster.
        ke_component_id spot_indices;  ///< The spot light indices of each cluster.
        ke_component_id spot_counts;   ///< The spot light count of each cluster.
        ke_component_id grid;          ///< The cluster grid parameters.
    } ke_render_cluster_resources;

#ifdef __cplusplus
}
#endif

#endif
