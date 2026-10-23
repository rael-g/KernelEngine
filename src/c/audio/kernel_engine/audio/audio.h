#ifndef KERNEL_ENGINE_AUDIO_AUDIO_H_
#define KERNEL_ENGINE_AUDIO_AUDIO_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/result/result.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** Opaque sound identifier owned by an audio backend. 0 is reserved as "invalid". */
    typedef uint32_t ke_audio_sound;
#define KE_AUDIO_SOUND_INVALID ((ke_audio_sound)0)

    /**
     * Audio playback.
     * Every slot is safe to call from a system body.
     */
    typedef struct ke_audio
    {
        void *handle;

        /**
         * Loads a sound for repeated playback; the backend autodetects the format.
         * @param path [borrowed,utf8] Filesystem path to the audio file.
         * @param out_sound [out] Receives the sound; KE_AUDIO_SOUND_INVALID on failure.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null path or out_sound;
         *         KE_RESULT_NOT_FOUND when the file cannot be opened; KE_RESULT_OUT_OF_MEMORY.
         */
        ke_result (*load_sound)(struct ke_audio *self, const char *path, ke_audio_sound *out_sound);

        /** Releases a previously loaded sound; safe on KE_AUDIO_SOUND_INVALID. */
        void (*unload_sound)(struct ke_audio *self, ke_audio_sound sound);

        /**
         * Plays a sound, restarting it from the beginning if already playing.
         * @param volume Playback volume in 0..1.
         * @param loop Non-zero to restart the sound when it ends.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for KE_AUDIO_SOUND_INVALID;
         *         KE_RESULT_NOT_FOUND for a sound that is not loaded; KE_RESULT_GENERAL when the
         *         backend cannot start it.
         */
        ke_result (*play)(struct ke_audio *self, ke_audio_sound sound, float volume, bool loop);

        /** Stops a playing sound; no-op when it is not playing. */
        void (*stop)(struct ke_audio *self, ke_audio_sound sound);

        /** Sets a global multiplier applied on top of per-sound volumes (0..1). */
        void (*set_master_volume)(struct ke_audio *self, float volume);

    } ke_audio;

    typedef struct ke_audio_handle
    {
        ke_audio *ref;
        void (*destroy)(ke_audio *self);
    } ke_audio_handle;

#ifdef __cplusplus
}
#endif

#endif
