#ifndef KERNEL_ENGINE_AUDIO_MODULE_SOUND_MODULE_H_
#define KERNEL_ENGINE_AUDIO_MODULE_SOUND_MODULE_H_

#include <kernel_engine/audio/audio.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/schedule/schedule.h>

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

/// [borrowed] The values the sound module is created with.
typedef struct ke_sound_module_config
{
    /// [borrowed,utf8] Directory a clip's path is joined to; copied. NULL uses the path as written.
    const char *root;
    /// The set the system joins.
    ke_schedule_set_id set;
} ke_sound_module_config;


typedef struct ke_sound_module ke_sound_module;

/// [owner]
typedef struct ke_sound_module_handle
{
    ke_sound_module *ref;
    void (*destroy)(ke_sound_module *self);
} ke_sound_module_handle;

/**
 * @brief Registers, in the config's set, the system that loads, plays and releases the clip of every
 *        ke_sound_component. Destroying the module stops every voice and releases every clip it holds.
 * @param schedule  [borrowed] Registers the system; must outlive the module.
 * @param ecs [borrowed] Resolves the component id.
 * @param audio [borrowed] Loads the clips and plays their voices; must outlive the module.
 * @param config [borrowed] Required; every field is read as given.
 * @param out_module [out] Receives the module; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p schedule, @p ecs, @p audio or
 *         @p out_module; KE_RESULT_OUT_OF_MEMORY; the code of the ECS or the schedule when it
 *         refuses the component or the system.
 */
KE_AUDIO_MODULE_API ke_result ke_sound_module_create(
    ke_schedule *schedule, ke_ecs *ecs, ke_audio *audio,
    const ke_sound_module_config *config,
    ke_sound_module_handle       *out_module);

#ifdef __cplusplus
}
#endif

#endif
