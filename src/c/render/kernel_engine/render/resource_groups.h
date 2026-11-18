#ifndef KERNEL_ENGINE_RENDER_RESOURCE_GROUPS_H_
#define KERNEL_ENGINE_RENDER_RESOURCE_GROUPS_H_

/// The names a pass publishes the resources it hands to others under, in the frame's publish.

/// The gbuffer's base color.
#define KE_RENDER_RESOURCE_GBUFFER_ALBEDO "gbuffer.albedo"
/// The gbuffer's world normal.
#define KE_RENDER_RESOURCE_GBUFFER_NORMAL "gbuffer.normal"
/// The gbuffer's emitted light.
#define KE_RENDER_RESOURCE_GBUFFER_EMISSIVE "gbuffer.emissive"
/// The directional shadow map.
#define KE_RENDER_RESOURCE_SHADOW_MAP "shadow.map"
/// The buffer holding the directional light's view-projection.
#define KE_RENDER_RESOURCE_SHADOW_LIGHT "shadow.light"
/// The clustered point lights.
#define KE_RENDER_RESOURCE_CLUSTER_POINT_LIGHTS "cluster.point_lights"
/// The clustered spot lights.
#define KE_RENDER_RESOURCE_CLUSTER_SPOT_LIGHTS "cluster.spot_lights"
/// The point light indices of each cluster.
#define KE_RENDER_RESOURCE_CLUSTER_POINT_INDICES "cluster.point_indices"
/// The point light count of each cluster.
#define KE_RENDER_RESOURCE_CLUSTER_POINT_COUNTS "cluster.point_counts"
/// The spot light indices of each cluster.
#define KE_RENDER_RESOURCE_CLUSTER_SPOT_INDICES "cluster.spot_indices"
/// The spot light count of each cluster.
#define KE_RENDER_RESOURCE_CLUSTER_SPOT_COUNTS "cluster.spot_counts"
/// The cluster grid's parameters.
#define KE_RENDER_RESOURCE_CLUSTER_GRID "cluster.grid"

#endif
