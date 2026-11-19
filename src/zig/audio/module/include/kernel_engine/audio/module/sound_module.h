#ifndef KERNEL_ENGINE_AUDIO_MODULE_SOUND_MODULE_H_
#define KERNEL_ENGINE_AUDIO_MODULE_SOUND_MODULE_H_

#include <kernel_engine/audio/audio.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/module/module.h>

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

/**
 * @brief Creates the module that loads, plays and releases the clip of every ke_sound_component;
 *        attaching it registers its system in the update schedule's post_update set. Destroying the
 *        module stops every voice and releases every clip it holds.
 * @param ecs [borrowed] Resolves the component id.
 * @param audio [borrowed] Loads the clips and plays their voices; must outlive the module.
 * @param out_module [out] Receives the module; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p ecs, @p audio or
 *         @p out_module; KE_RESULT_OUT_OF_MEMORY; the ECS's code when it refuses the component.
 */
KE_AUDIO_MODULE_API ke_result ke_sound_create(
    ke_ecs *ecs, ke_audio *audio,
    ke_module_handle *out_module);

#ifdef __cplusplus
}
#endif

#endif
