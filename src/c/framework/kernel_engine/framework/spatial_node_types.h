#ifndef KERNEL_ENGINE_FRAMEWORK_SPATIAL_NODE_TYPES_H_
#define KERNEL_ENGINE_FRAMEWORK_SPATIAL_NODE_TYPES_H_

#include <kernel_engine/ecs/component_fields.h>
#include <kernel_engine/framework/node_types.h>

/// How a 3D node is placed when it is born: at the origin, unrotated, at unit scale.
static const ke_transform_component ke_transform_node_initial = { .rotation = { 0.0f, 0.0f, 0.0f, 1.0f }, .scale = { 1.0f, 1.0f, 1.0f } };
/// How a 2D node is placed when it is born: at the origin, unrotated, at unit scale.
static const ke_transform2d_component ke_transform2d_node_initial = { .scale = { 1.0f, 1.0f } };
/// The components of the 2D node type and how they are born.
static const ke_node_with ke_transform2d_node_with[] = { { &ke_transform2d_component_desc, &ke_transform2d_node_initial, sizeof ke_transform2d_node_initial } };
/// The components of the 3D node type and how they are born.
static const ke_node_with ke_transform_node_with[] = { { &ke_transform_component_desc, &ke_transform_node_initial, sizeof ke_transform_node_initial } };

/// The node types space makes: `node`, which carries no component and only places its children in the tree,
/// and the 2D and 3D nodes, which carry a place, for a host to register through `register_type`.
static const ke_node_type_desc ke_spatial_node_types[] = {
    { .name = "node" },
    { .name = "transform2d", .with = ke_transform2d_node_with, .with_count = 1 },
    { .name = "transform", .with = ke_transform_node_with, .with_count = 1 },
};

/// The number of entries in `ke_spatial_node_types`.
#define KE_SPATIAL_NODE_TYPE_COUNT 3

#endif
