#ifndef KERNEL_ENGINE_RENDER_RESOURCE_GROUPS_H_
#define KERNEL_ENGINE_RENDER_RESOURCE_GROUPS_H_

/// @file
/// The names inside a resource group. A pass that writes several resources a reader takes
/// together is given one group name by its host, and publishes each resource under that name
/// followed by one of the suffixes below; a reader given the same group name finds them so.

/// The gbuffer's base color.
#define KE_RENDER_GBUFFER_ALBEDO ".albedo"
/// The gbuffer's world normal.
#define KE_RENDER_GBUFFER_NORMAL ".normal"
/// The gbuffer's emitted light.
#define KE_RENDER_GBUFFER_EMISSIVE ".emissive"

/// The buffer holding the shadow's light view-projection. The shadow map is the group itself.
#define KE_RENDER_SHADOW_LIGHT ".light"
/// The depth attachment the shadow map is drawn with.
#define KE_RENDER_SHADOW_DEPTH ".depth"

/// The clustered point lights. The group itself is the tag the cluster pass writes.
#define KE_RENDER_CLUSTER_POINT_LIGHTS ".point_lights"
/// The clustered spot lights.
#define KE_RENDER_CLUSTER_SPOT_LIGHTS ".spot_lights"
/// The point light indices of each cluster.
#define KE_RENDER_CLUSTER_POINT_INDICES ".point_indices"
/// The point light count of each cluster.
#define KE_RENDER_CLUSTER_POINT_COUNTS ".point_counts"
/// The spot light indices of each cluster.
#define KE_RENDER_CLUSTER_SPOT_INDICES ".spot_indices"
/// The spot light count of each cluster.
#define KE_RENDER_CLUSTER_SPOT_COUNTS ".spot_counts"
/// The cluster grid parameters.
#define KE_RENDER_CLUSTER_GRID ".grid"

#endif
