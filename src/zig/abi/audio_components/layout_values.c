#include <stddef.h>
#include <kernel_engine/audio/components.h>
const unsigned long long layout_values[] = {
    sizeof(ke_audio_player_component),
    offsetof(ke_audio_player_component, path),
    offsetof(ke_audio_player_component, volume),
    0,
};
