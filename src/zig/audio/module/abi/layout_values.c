#include <stddef.h>
#include <kernel_engine/audio/module/audio_module.h>
#include <kernel_engine/audio/module/audio_module_log.h>
#include <kernel_engine/audio/module/sound_module.h>
const unsigned long long layout_values[] = {
    sizeof(ke_sound_module_config),
    offsetof(ke_sound_module_config, root),
    sizeof(ke_sound_module_handle),
    offsetof(ke_sound_module_handle, ref),
    offsetof(ke_sound_module_handle, destroy),
    0,
};
