
#ifndef KERNEL_ENGINE_AUDIO_MODULE_AUDIO_MODULE_H_
#define KERNEL_ENGINE_AUDIO_MODULE_AUDIO_MODULE_H_

#include <kernel_engine/framework/scene_component_set.h>

#ifndef KE_AUDIO_MODULE_API
#  if defined(_WIN32) || defined(__CYGWIN__)
#    if defined(KE_AUDIO_MODULE_STATIC)
#      define KE_AUDIO_MODULE_API
#    elif defined(KE_AUDIO_MODULE_EXPORT)
#      define KE_AUDIO_MODULE_API __declspec(dllexport)
#    else
#      define KE_AUDIO_MODULE_API __declspec(dllimport)
#    endif
#  else
#    define KE_AUDIO_MODULE_API __attribute__((visibility("default")))
#  endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// @brief Returns the set of audio's scene components: the audio player, with its field table, so
///        an [entity.components.audio_player] block applies. The set holds no state.
KE_AUDIO_MODULE_API ke_scene_component_set_handle ke_audio_scene_components_create(void);

#ifdef __cplusplus
}
#endif

#endif
