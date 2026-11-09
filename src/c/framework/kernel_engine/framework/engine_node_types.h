#ifndef KERNEL_ENGINE_FRAMEWORK_ENGINE_NODE_TYPES_H_
#define KERNEL_ENGINE_FRAMEWORK_ENGINE_NODE_TYPES_H_

#include <kernel_engine/audio/components.h>
#include <kernel_engine/framework/node_types.h>
#include <kernel_engine/physics/components.h>
#include <kernel_engine/render/components.h>
#include <kernel_engine/render/ui/components.h>
#include <kernel_engine/spatial/transform.h>

/// How a 3D node is placed when it is born: at the origin, unrotated, at unit scale.
static const ke_transform_component ke_transform_node_initial = { .rotation = { 0.0f, 0.0f, 0.0f, 1.0f }, .scale = { 1.0f, 1.0f, 1.0f } };
/// How a 2D node is placed when it is born: at the origin, unrotated, at unit scale.
static const ke_transform2d_component ke_transform2d_node_initial = { .scale = { 1.0f, 1.0f } };
/// A camera node is born perspective, 60 degrees wide, seeing every layer from 0.1 to 1000.
static const ke_camera_component ke_camera_node_initial = { .fov = 60.0f, .near_plane = 0.1f, .far_plane = 1000.0f, .orthographic_size = 5.0f, .cull_mask = 0xFFFFFFFFu };
/// A directional light node is born white, at unit intensity, with a dim ambient term.
static const ke_directional_light_component ke_directional_light_node_initial = { .direction = { 0.2f, 1.0f, 0.5f }, .color = { 1.0f, 1.0f, 1.0f }, .intensity = 1.0f, .ambient = { 0.2f, 0.2f, 0.2f } };
/// A point light node is born white, at unit intensity, reaching 10 units.
static const ke_point_light_component ke_point_light_node_initial = { .color = { 1.0f, 1.0f, 1.0f }, .intensity = 1.0f, .radius = 10.0f };
/// A spot light node is born white, pointing down, reaching 20 units in a 25 to 35 degree cone.
static const ke_spot_light_component ke_spot_light_node_initial = { .direction = { 0.0f, -1.0f, 0.0f }, .color = { 1.0f, 1.0f, 1.0f }, .intensity = 1.0f, .range = 20.0f, .inner_angle = 25.0f, .outer_angle = 35.0f };
/// An ambient light node is born a faint grey.
static const ke_ambient_light_component ke_ambient_light_node_initial = { .color = { 0.05f, 0.05f, 0.05f } };
/// A mesh node is born opaque, white and fully rough, on the first layer.
static const ke_mesh_component ke_mesh_node_initial = { .base_color = { 1.0f, 1.0f, 1.0f, 1.0f }, .roughness = 1.0f, .alpha_mode = KE_ALPHA_MODE_OPAQUE, .alpha_cutoff = 0.5f, .ior = 1.5f, .distortion_strength = 0.05f, .layers = 1 };
/// A sprite node is born opaque and white, one unit square, showing its whole texture around its centre.
static const ke_sprite2d_component ke_sprite2d_node_initial = { .region = { 0.0f, 0.0f, 1.0f, 1.0f }, .size = { 1.0f, 1.0f }, .pivot = { 0.5f, 0.5f }, .color = { 1.0f, 1.0f, 1.0f, 1.0f }, .alpha_mode = KE_ALPHA_MODE_OPAQUE, .alpha_cutoff = 0.5f };
/// A label node is born white, at 32 pixels.
static const ke_label_component ke_label_node_initial = { .font_size = 32.0f, .color = { 1.0f, 1.0f, 1.0f, 1.0f } };
/// A body node is born at full gravity.
static const ke_body2d_component ke_body2d_node_initial = { .gravity_scale = 1.0f };
/// A collider node is born a unit box of unit density and some friction, on the first layer, meeting every layer.
static const ke_collider2d_component ke_collider2d_node_initial = { .half_extents = { 0.5f, 0.5f }, .radius = 0.5f, .density = 1.0f, .friction = 0.3f, .layer = 1, .mask = 0xFFFFFFFFu };
/// A sound node is born at full volume and its recorded pitch.
static const ke_sound_component ke_sound_node_initial = { .volume = 1.0f, .pitch = 1.0f };

/// The components of the ambient light node type and how they are born.
static const ke_node_with ke_ambient_light_node_with[] = { { "ambient_light", &ke_ambient_light_node_initial }, { "transform", &ke_transform_node_initial } };
/// The components of the body node type and how they are born.
static const ke_node_with ke_body2d_node_with[] = { { "body2d", &ke_body2d_node_initial }, { "transform2d", &ke_transform2d_node_initial } };
/// The components of the camera node type and how they are born.
static const ke_node_with ke_camera_node_with[] = { { "camera", &ke_camera_node_initial }, { "transform", &ke_transform_node_initial } };
/// The components of the collider node type and how they are born.
static const ke_node_with ke_collider2d_node_with[] = { { "collider2d", &ke_collider2d_node_initial }, { "transform2d", &ke_transform2d_node_initial } };
/// The components of the directional light node type and how they are born.
static const ke_node_with ke_directional_light_node_with[] = { { "directional_light", &ke_directional_light_node_initial }, { "transform", &ke_transform_node_initial } };
/// The components of the label node type and how they are born.
static const ke_node_with ke_label_node_with[] = { { "label", &ke_label_node_initial }, { "transform", &ke_transform_node_initial } };
/// The components of the mesh node type and how they are born.
static const ke_node_with ke_mesh_node_with[] = { { "mesh", &ke_mesh_node_initial }, { "transform", &ke_transform_node_initial } };
/// The components of the point light node type and how they are born.
static const ke_node_with ke_point_light_node_with[] = { { "point_light", &ke_point_light_node_initial }, { "transform", &ke_transform_node_initial } };
/// The components of the skybox node type and how they are born.
static const ke_node_with ke_skybox_node_with[] = { { "skybox", NULL }, { "transform", &ke_transform_node_initial } };
/// The components of the sound node type and how they are born.
static const ke_node_with ke_sound_node_with[] = { { "sound", &ke_sound_node_initial }, { "transform", &ke_transform_node_initial } };
/// The components of the spot light node type and how they are born.
static const ke_node_with ke_spot_light_node_with[] = { { "spot_light", &ke_spot_light_node_initial }, { "transform", &ke_transform_node_initial } };
/// The components of the sprite node type and how they are born.
static const ke_node_with ke_sprite2d_node_with[] = { { "sprite2d", &ke_sprite2d_node_initial }, { "transform2d", &ke_transform2d_node_initial } };
/// The components of the 2D node type and how they are born.
static const ke_node_with ke_transform2d_node_with[] = { { "transform2d", &ke_transform2d_node_initial } };
/// The components of the 3D node type and how they are born.
static const ke_node_with ke_transform_node_with[] = { { "transform", &ke_transform_node_initial } };

/// The node types the engine's components make, for a host to register through `register_type`.
static const ke_node_type_desc ke_engine_node_types[] = {
    { .name = "ambient_light", .with = ke_ambient_light_node_with, .with_count = 2 },
    { .name = "body2d", .with = ke_body2d_node_with, .with_count = 2 },
    { .name = "camera", .with = ke_camera_node_with, .with_count = 2 },
    { .name = "collider2d", .with = ke_collider2d_node_with, .with_count = 2 },
    { .name = "directional_light", .with = ke_directional_light_node_with, .with_count = 2 },
    { .name = "label", .with = ke_label_node_with, .with_count = 2 },
    { .name = "mesh", .with = ke_mesh_node_with, .with_count = 2 },
    { .name = "point_light", .with = ke_point_light_node_with, .with_count = 2 },
    { .name = "skybox", .with = ke_skybox_node_with, .with_count = 2 },
    { .name = "sound", .with = ke_sound_node_with, .with_count = 2 },
    { .name = "spot_light", .with = ke_spot_light_node_with, .with_count = 2 },
    { .name = "sprite2d", .with = ke_sprite2d_node_with, .with_count = 2 },
    { .name = "transform2d", .with = ke_transform2d_node_with, .with_count = 1 },
    { .name = "transform", .with = ke_transform_node_with, .with_count = 1 },
};

/// The number of entries in `ke_engine_node_types`.
#define KE_ENGINE_NODE_TYPE_COUNT 14

#endif
