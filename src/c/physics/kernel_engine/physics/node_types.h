#ifndef KERNEL_ENGINE_PHYSICS_NODE_TYPES_H_
#define KERNEL_ENGINE_PHYSICS_NODE_TYPES_H_

#include <kernel_engine/physics/component_fields.h>
#include <kernel_engine/framework/spatial_node_types.h>

/// A body node is born at full gravity.
static const ke_body2d_component ke_body2d_node_initial = { .gravity_scale = 1.0f };
/// A collider node is born a unit box of unit density and some friction, on the first layer, meeting every layer.
static const ke_collider2d_component ke_collider2d_node_initial = { .half_extents = { 0.5f, 0.5f }, .radius = 0.5f, .density = 1.0f, .friction = 0.3f, .layer = 1, .mask = 0xFFFFFFFFu };

/// The components of the body node type and how they are born.
static const ke_node_with ke_body2d_node_with[] = { { &ke_body2d_component_desc, &ke_body2d_node_initial, sizeof ke_body2d_node_initial }, { &ke_transform2d_component_desc, &ke_transform2d_node_initial, sizeof ke_transform2d_node_initial } };
/// The components of the collider node type and how they are born.
static const ke_node_with ke_collider2d_node_with[] = { { &ke_collider2d_component_desc, &ke_collider2d_node_initial, sizeof ke_collider2d_node_initial }, { &ke_transform2d_component_desc, &ke_transform2d_node_initial, sizeof ke_transform2d_node_initial } };

/// The node types physics' components make, for a host to register through `register_type`.
static const ke_node_type_desc ke_physics_node_types[] = {
    { .name = "body2d", .with = ke_body2d_node_with, .with_count = 2 },
    { .name = "collider2d", .with = ke_collider2d_node_with, .with_count = 2 },
};

/// The number of entries in `ke_physics_node_types`.
#define KE_PHYSICS_NODE_TYPE_COUNT 2

#endif
