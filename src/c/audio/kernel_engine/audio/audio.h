#ifndef KERNEL_ENGINE_AUDIO_AUDIO_H_
#define KERNEL_ENGINE_AUDIO_AUDIO_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/common/export.h>
#include <kernel_engine/common/types.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_AUDIO "ke_audio"

    /** Opaque sound identifier owned by an audio backend. 0 is reserved as "invalid". */
    typedef uint32_t ke_audio_sound;
#define KE_AUDIO_SOUND_INVALID ((ke_audio_sound)0)

    /**
     * Audio playback. Concrete implementations ship as separate plugins
     * (miniaudio, FMOD, ...). Every slot is safe to call from a system body — backends
     * marshal internally to their own audio thread.
     */
    typedef struct ke_audio
    {
        void *handle;

        /**
         * Loads a sound for repeated playback; the backend autodetects the format.
         * @param path [borrowed,utf8] Filesystem path to the audio file.
         * @return KE_AUDIO_SOUND_INVALID on error.
         */
        ke_audio_sound (*load_sound)(struct ke_audio *self, const char *path, ke_error **out_error);

        /** Releases a previously loaded sound; safe on KE_AUDIO_SOUND_INVALID. */
        void (*unload_sound)(struct ke_audio *self, ke_audio_sound sound);

        /**
         * Plays a sound, restarting it from the beginning if already playing.
         * @param volume Playback volume in 0..1.
         * @param loop Non-zero to restart the sound when it ends.
         */
        bool (*play)(struct ke_audio *self, ke_audio_sound sound, float volume, ke_bool loop, ke_error **out_error);

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
