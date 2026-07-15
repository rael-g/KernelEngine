#pragma once

#include <kernel_engine/audio/audio.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_AUDIO_MINIAUDIO_EXPORT
        #define KE_AUDIO_MINIAUDIO_API __declspec(dllexport)
    #elif defined(KE_AUDIO_MINIAUDIO_STATIC)
        #define KE_AUDIO_MINIAUDIO_API
    #else
        #define KE_AUDIO_MINIAUDIO_API __declspec(dllimport)
    #endif
#else
    #define KE_AUDIO_MINIAUDIO_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// @brief Construction parameters for the miniaudio-backed ke_audio backend.
typedef struct ke_audio_miniaudio_params
{
    struct ke_logger    *logger;    ///< Optional; may be NULL
} ke_audio_miniaudio_params;

/// @brief Creates a miniaudio-backed ke_audio. Spawns an internal audio thread that owns the
///        hardware device; sound playback marshals from the caller (typically ke.sim) into it.
/// @return Handle whose @c ref is NULL on failure.
KE_AUDIO_MINIAUDIO_API ke_audio_handle ke_audio_miniaudio_create(
    const ke_audio_miniaudio_params *params,
    ke_error **out_error);

#ifdef __cplusplus
}
#endif
