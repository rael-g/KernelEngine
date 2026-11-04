#include <stddef.h>
#include <kernel_engine/audio/audio.h>
const unsigned long long layout_values[] = {
    sizeof(ke_audio),
    offsetof(ke_audio, handle),
    offsetof(ke_audio, load_sound),
    offsetof(ke_audio, unload_sound),
    offsetof(ke_audio, voice_start),
    offsetof(ke_audio, voice_playing),
    offsetof(ke_audio, voice_stop),
    offsetof(ke_audio, set_master_volume),
    sizeof(ke_audio_handle),
    offsetof(ke_audio_handle, ref),
    offsetof(ke_audio_handle, destroy),
    0,
};
