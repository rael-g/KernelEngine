#ifndef KERNEL_ENGINE_RENDER_UI_NODE_TYPES_H_
#define KERNEL_ENGINE_RENDER_UI_NODE_TYPES_H_

#include <kernel_engine/render/ui/component_fields.h>
#include <kernel_engine/framework/spatial_node_types.h>

/// A label node is born white, at 32 pixels.
static const ke_label_component ke_label_node_initial = { .font_size = 32.0f, .color = { 1.0f, 1.0f, 1.0f, 1.0f } };

/// The components of the label node type and how they are born.
static const ke_node_with ke_label_node_with[] = { { &ke_label_component_desc, &ke_label_node_initial, sizeof ke_label_node_initial }, { &ke_transform_component_desc, &ke_transform_node_initial, sizeof ke_transform_node_initial } };

/// The node types the interface's components make, for a host to register through `register_type`.
static const ke_node_type_desc ke_ui_node_types[] = {
    { .name = "label", .with = ke_label_node_with, .with_count = 2 },
};

/// The number of entries in `ke_ui_node_types`.
#define KE_UI_NODE_TYPE_COUNT 1

#endif
