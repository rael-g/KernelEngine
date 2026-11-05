#include <stddef.h>
#include <kernel_engine/audio/components.h>
const unsigned long long layout_values[] = {
    sizeof(ke_sound_component),
    offsetof(ke_sound_component, path),
    offsetof(ke_sound_component, volume),
    offsetof(ke_sound_component, pitch),
    offsetof(ke_sound_component, loop),
    offsetof(ke_sound_component, playing),
    offsetof(ke_sound_component, release),
    offsetof(ke_sound_component, clip),
    offsetof(ke_sound_component, voice),
    0,
};
