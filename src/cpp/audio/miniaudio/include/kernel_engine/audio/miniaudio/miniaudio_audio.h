#pragma once

#include <kernel_engine/audio/audio.h>
#include <kernel_engine/audio/miniaudio/audio_export.h>

#ifdef __cplusplus
extern "C" {
#endif

/// @brief Construction parameters for the miniaudio-backed ke_audio backend.
typedef struct ke_audio_miniaudio_params
{
    struct ke_allocator *allocator; ///< Allocator owns the backend struct + internal bookkeeping
    struct ke_logger    *logger;    ///< Optional; may be NULL
} ke_audio_miniaudio_params;

/// @brief Creates a miniaudio-backed ke_audio. Spawns an internal audio thread that owns the
///        hardware device; sound playback marshals from the caller (typically ke.sim) into it.
KE_AUDIO_MINIAUDIO_API ke_result ke_audio_miniaudio_create(
    const ke_audio_miniaudio_params *params,
    ke_audio **out,
    ke_error **out_error);

#ifdef __cplusplus
}
#endif
