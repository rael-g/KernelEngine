#include <stddef.h>
#include <kernel_engine/audio/module/audio_module.h>
#include <kernel_engine/audio/module/audio_module_log.h>
#include <kernel_engine/audio/module/audio_player_create.h>
const unsigned long long layout_values[] = {
    sizeof(ke_audio_player_module_config),
    offsetof(ke_audio_player_module_config, root),
    sizeof(ke_audio_player_module_handle),
    offsetof(ke_audio_player_module_handle, ref),
    offsetof(ke_audio_player_module_handle, destroy),
    0,
};
