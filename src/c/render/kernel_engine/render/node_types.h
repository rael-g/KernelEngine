#ifndef KERNEL_ENGINE_RENDER_NODE_TYPES_H_
#define KERNEL_ENGINE_RENDER_NODE_TYPES_H_

#include <kernel_engine/render/component_fields.h>
#include <kernel_engine/framework/spatial_node_types.h>

/// An ambient light node is born a faint grey.
static const ke_ambient_light_component ke_ambient_light_node_initial = { .color = { 0.05f, 0.05f, 0.05f } };
/// A camera node is born perspective, 60 degrees wide, seeing every layer from 0.1 to 1000.
static const ke_camera_component ke_camera_node_initial = { .fov = 60.0f, .near_plane = 0.1f, .far_plane = 1000.0f, .orthographic_size = 5.0f, .cull_mask = 0xFFFFFFFFu };
/// A directional light node is born white, at unit intensity, with a dim ambient term.
static const ke_directional_light_component ke_directional_light_node_initial = { .direction = { 0.2f, 1.0f, 0.5f }, .color = { 1.0f, 1.0f, 1.0f }, .intensity = 1.0f, .ambient = { 0.2f, 0.2f, 0.2f } };
/// A mesh node is born opaque, white and fully rough, on the first layer.
static const ke_mesh_component ke_mesh_node_initial = { .base_color = { 1.0f, 1.0f, 1.0f, 1.0f }, .roughness = 1.0f, .alpha_mode = KE_ALPHA_MODE_OPAQUE, .alpha_cutoff = 0.5f, .ior = 1.5f, .distortion_strength = 0.05f, .layers = 1 };
/// A point light node is born white, at unit intensity, reaching 10 units.
static const ke_point_light_component ke_point_light_node_initial = { .color = { 1.0f, 1.0f, 1.0f }, .intensity = 1.0f, .radius = 10.0f };
/// A spot light node is born white, pointing down, reaching 20 units in a 25 to 35 degree cone.
static const ke_spot_light_component ke_spot_light_node_initial = { .direction = { 0.0f, -1.0f, 0.0f }, .color = { 1.0f, 1.0f, 1.0f }, .intensity = 1.0f, .range = 20.0f, .inner_angle = 25.0f, .outer_angle = 35.0f };
/// A sprite node is born opaque and white, one unit square, showing its whole texture around its centre.
static const ke_sprite2d_component ke_sprite2d_node_initial = { .region = { 0.0f, 0.0f, 1.0f, 1.0f }, .size = { 1.0f, 1.0f }, .pivot = { 0.5f, 0.5f }, .color = { 1.0f, 1.0f, 1.0f, 1.0f }, .alpha_mode = KE_ALPHA_MODE_OPAQUE, .alpha_cutoff = 0.5f };

/// The components of the ambient light node type and how they are born.
static const ke_node_with ke_ambient_light_node_with[] = { { &ke_ambient_light_component_desc, &ke_ambient_light_node_initial, sizeof ke_ambient_light_node_initial }, { &ke_transform_component_desc, &ke_transform_node_initial, sizeof ke_transform_node_initial } };
/// The components of the camera node type and how they are born.
static const ke_node_with ke_camera_node_with[] = { { &ke_camera_component_desc, &ke_camera_node_initial, sizeof ke_camera_node_initial }, { &ke_transform_component_desc, &ke_transform_node_initial, sizeof ke_transform_node_initial } };
/// The components of the directional light node type and how they are born.
static const ke_node_with ke_directional_light_node_with[] = { { &ke_directional_light_component_desc, &ke_directional_light_node_initial, sizeof ke_directional_light_node_initial }, { &ke_transform_component_desc, &ke_transform_node_initial, sizeof ke_transform_node_initial } };
/// The components of the mesh node type and how they are born.
static const ke_node_with ke_mesh_node_with[] = { { &ke_mesh_component_desc, &ke_mesh_node_initial, sizeof ke_mesh_node_initial }, { &ke_transform_component_desc, &ke_transform_node_initial, sizeof ke_transform_node_initial } };
/// The components of the point light node type and how they are born.
static const ke_node_with ke_point_light_node_with[] = { { &ke_point_light_component_desc, &ke_point_light_node_initial, sizeof ke_point_light_node_initial }, { &ke_transform_component_desc, &ke_transform_node_initial, sizeof ke_transform_node_initial } };
/// The components of the skybox node type and how they are born.
static const ke_node_with ke_skybox_node_with[] = { { &ke_skybox_component_desc, NULL, 0 }, { &ke_transform_component_desc, &ke_transform_node_initial, sizeof ke_transform_node_initial } };
/// The components of the spot light node type and how they are born.
static const ke_node_with ke_spot_light_node_with[] = { { &ke_spot_light_component_desc, &ke_spot_light_node_initial, sizeof ke_spot_light_node_initial }, { &ke_transform_component_desc, &ke_transform_node_initial, sizeof ke_transform_node_initial } };
/// The components of the sprite node type and how they are born.
static const ke_node_with ke_sprite2d_node_with[] = { { &ke_sprite2d_component_desc, &ke_sprite2d_node_initial, sizeof ke_sprite2d_node_initial }, { &ke_transform2d_component_desc, &ke_transform2d_node_initial, sizeof ke_transform2d_node_initial } };

/// The node types render's components make, for a host to register through `register_type`.
static const ke_node_type_desc ke_render_node_types[] = {
    { .name = "ambient_light", .with = ke_ambient_light_node_with, .with_count = 2 },
    { .name = "camera", .with = ke_camera_node_with, .with_count = 2 },
    { .name = "directional_light", .with = ke_directional_light_node_with, .with_count = 2 },
    { .name = "mesh", .with = ke_mesh_node_with, .with_count = 2 },
    { .name = "point_light", .with = ke_point_light_node_with, .with_count = 2 },
    { .name = "skybox", .with = ke_skybox_node_with, .with_count = 2 },
    { .name = "spot_light", .with = ke_spot_light_node_with, .with_count = 2 },
    { .name = "sprite2d", .with = ke_sprite2d_node_with, .with_count = 2 },
};

/// The number of entries in `ke_render_node_types`.
#define KE_RENDER_NODE_TYPE_COUNT 8

#endif
