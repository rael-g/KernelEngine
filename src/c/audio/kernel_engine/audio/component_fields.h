#ifndef KERNEL_ENGINE_AUDIO_COMPONENT_FIELDS_H_
#define KERNEL_ENGINE_AUDIO_COMPONENT_FIELDS_H_

#include <kernel_engine/ecs/component_field.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/audio/components.h>
#include <stdalign.h>
#include <stddef.h>
#include <stdint.h>

/// The fields of `ke_sound_component` a scene or the game writes by name: each name, kind, place, size, default
/// and, for an enumeration, its value names.
static const ke_component_field ke_sound_component_fields[] = {
    { "path", KE_VARIANT_STRING, offsetof(ke_sound_component, path), sizeof(((ke_sound_component *)0)->path), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "volume", KE_VARIANT_FLOAT, offsetof(ke_sound_component, volume), sizeof(((ke_sound_component *)0)->volume), { KE_VARIANT_FLOAT, { .f = 1.0 } }, NULL, 0 },
    { "pitch", KE_VARIANT_FLOAT, offsetof(ke_sound_component, pitch), sizeof(((ke_sound_component *)0)->pitch), { KE_VARIANT_FLOAT, { .f = 1.0 } }, NULL, 0 },
    { "loop", KE_VARIANT_BOOL, offsetof(ke_sound_component, loop), sizeof(((ke_sound_component *)0)->loop), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "playing", KE_VARIANT_BOOL, offsetof(ke_sound_component, playing), sizeof(((ke_sound_component *)0)->playing), { KE_VARIANT_NULL, { 0 } }, NULL, 0 },
    { "release", KE_VARIANT_INT, offsetof(ke_sound_component, release), sizeof(((ke_sound_component *)0)->release), { KE_VARIANT_NULL, { 0 } }, (const char *const[]){ "keep", "when_done" }, 2 },
};

/// How `ke_sound_component` is registered: its name, size, alignment and field table.
static const ke_component_desc ke_sound_component_desc = { KE_COMPONENT_NAME_SOUND, sizeof(ke_sound_component), alignof(ke_sound_component), ke_sound_component_fields, (uint32_t)(sizeof ke_sound_component_fields / sizeof ke_sound_component_fields[0]) };

#endif
