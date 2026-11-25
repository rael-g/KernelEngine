#ifndef KERNEL_ENGINE_AUDIO_NODE_TYPES_H_
#define KERNEL_ENGINE_AUDIO_NODE_TYPES_H_

#include <kernel_engine/audio/component_fields.h>
#include <kernel_engine/framework/spatial_node_types.h>

/// A sound node is born at full volume and its recorded pitch.
static const ke_sound_component ke_sound_node_initial = { .volume = 1.0f, .pitch = 1.0f };

/// The components of the sound node type and how they are born.
static const ke_node_with ke_sound_node_with[] = { { &ke_sound_component_desc, &ke_sound_node_initial, sizeof ke_sound_node_initial }, { &ke_transform_component_desc, &ke_transform_node_initial, sizeof ke_transform_node_initial } };

/// The node types audio's components make, for a host to register through `register_type`.
static const ke_node_type_desc ke_audio_node_types[] = {
    { .name = "sound", .with = ke_sound_node_with, .with_count = 2 },
};

/// The number of entries in `ke_audio_node_types`.
#define KE_AUDIO_NODE_TYPE_COUNT 1

#endif
