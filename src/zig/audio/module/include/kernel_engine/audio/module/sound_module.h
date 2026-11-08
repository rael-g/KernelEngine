#ifndef KERNEL_ENGINE_AUDIO_MODULE_SOUND_MODULE_H_
#define KERNEL_ENGINE_AUDIO_MODULE_SOUND_MODULE_H_

#include <kernel_engine/audio/audio.h>
#include <kernel_engine/configuration/configuration.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/runtime/runtime.h>

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

/// The values the sound module is created with.
typedef struct ke_sound_module_config
{
    /// [borrowed,utf8] Directory a clip's path is joined to; copied. NULL uses the path as written.
    const char *root;
} ke_sound_module_config;

/** [defaults] The module a caller gets when it sets nothing: paths used as written. */
static const ke_sound_module_config ke_sound_module_config_defaults = {
    .root = NULL,
};

/** The keys a configuration section fills a ke_sound_module_config from. */
static const ke_config_field ke_sound_module_config_fields[] = {
    KE_CONFIG_FIELD(ke_sound_module_config, root),
};

typedef struct ke_sound_module ke_sound_module;

/// [owner]
typedef struct ke_sound_module_handle
{
    ke_sound_module *ref;
    void (*destroy)(ke_sound_module *self);
} ke_sound_module_handle;

/**
 * @brief Registers the post-update-phase system that loads, plays and releases the clip of every
 *        ke_sound_component. Destroying the module stops every voice and releases every clip it holds.
 * @param runtime [borrowed] Registers the system; must outlive the module.
 * @param ecs [borrowed] Resolves the component id.
 * @param audio [borrowed] Loads the clips and plays their voices; must outlive the module.
 * @param config [borrowed,optional] NULL takes every default.
 * @param out_module [out] Receives the module; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p runtime, @p ecs, @p audio or
 *         @p out_module; KE_RESULT_OUT_OF_MEMORY; the code of the ECS or the runtime when it
 *         refuses the component or the system.
 */
KE_AUDIO_MODULE_API ke_result ke_sound_module_create(
    ke_runtime *runtime, ke_ecs *ecs, ke_audio *audio,
    const ke_sound_module_config *config,
    ke_sound_module_handle       *out_module);

#ifdef __cplusplus
}
#endif

#endif
