#ifndef KERNEL_ENGINE_FRAMEWORK_ENGINE_NODE_TYPES_H_
#define KERNEL_ENGINE_FRAMEWORK_ENGINE_NODE_TYPES_H_

#include <kernel_engine/framework/node_types.h>

static const char *const ke_ambient_light_node_with[] = { "ambient_light", "transform" };
static const char *const ke_body2d_node_with[] = { "body2d", "transform2d" };
static const char *const ke_camera_node_with[] = { "camera", "transform" };
static const char *const ke_collider2d_node_with[] = { "collider2d", "transform2d" };
static const char *const ke_directional_light_node_with[] = { "directional_light", "transform" };
static const char *const ke_label_node_with[] = { "label", "transform" };
static const char *const ke_mesh_node_with[] = { "mesh", "transform" };
static const char *const ke_point_light_node_with[] = { "point_light", "transform" };
static const char *const ke_skybox_node_with[] = { "skybox", "transform" };
static const char *const ke_sound_node_with[] = { "sound", "transform" };
static const char *const ke_spot_light_node_with[] = { "spot_light", "transform" };
static const char *const ke_sprite2d_node_with[] = { "sprite2d", "transform2d" };
static const char *const ke_transform2d_node_with[] = { "transform2d" };
static const char *const ke_transform_node_with[] = { "transform" };

/** Every node type the engine's components describe: a name and the components it carries. */
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

#define KE_ENGINE_NODE_TYPE_COUNT 14

#endif
