#ifndef KERNEL_ENGINE_AUDIO_MINIAUDIO_MINIAUDIO_AUDIO_H_
#define KERNEL_ENGINE_AUDIO_MINIAUDIO_MINIAUDIO_AUDIO_H_

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

/**
 * @brief Creates a ke_audio backend for the audio output device.
 * @param out_audio [out] Receives the backend; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p out_audio; KE_RESULT_OUT_OF_MEMORY;
 *         KE_RESULT_GENERAL when the audio engine cannot start.
 */
KE_AUDIO_MINIAUDIO_API ke_result ke_audio_miniaudio_create(ke_audio_handle *out_audio);

#ifdef __cplusplus
}
#endif

#endif
