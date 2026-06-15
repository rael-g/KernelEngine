#ifndef KERNEL_ENGINE_AUDIO_AUDIO_H_
#define KERNEL_ENGINE_AUDIO_AUDIO_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/common/export.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_AUDIO "ke_audio"

    /// @brief Opaque sound identifier owned by an audio backend. 0 is reserved as "invalid".
    typedef uint32_t ke_audio_sound;
#define KE_AUDIO_SOUND_INVALID ((ke_audio_sound)0)

    /// @brief ABI-stable vtable for audio playback. Concrete implementations are provided as
    ///        separate plugins (e.g. miniaudio, FMOD). All function-pointer calls are safe from
    ///        ke.sim — backends internally marshal to their own audio thread.
    typedef struct ke_audio
    {
        void *handle;

        /// @brief Destroys the backend; stops all playback, frees loaded sounds.
        void (*destroy)(struct ke_audio *self);

        /// @brief Loads a sound from @p path (format autodetected by the backend) and returns a
        ///        handle suitable for repeated playback. Returns KE_AUDIO_SOUND_INVALID on error.
        ke_result (*load_sound)(struct ke_audio *self, const char *path, ke_audio_sound *out);

        /// @brief Releases a previously loaded sound; safe on KE_AUDIO_SOUND_INVALID.
        void (*unload_sound)(struct ke_audio *self, ke_audio_sound sound);

        /// @brief Plays @p sound at @p volume (0..1). If @p loop is non-zero the sound restarts
        ///        on end. Calling on an already-playing handle restarts playback from the start.
        ke_result (*play)(struct ke_audio *self, ke_audio_sound sound, float volume, bool loop);

        /// @brief Stops a currently playing sound; no-op when @p sound is not playing.
        void (*stop)(struct ke_audio *self, ke_audio_sound sound);

        /// @brief Sets a global volume multiplier applied on top of per-sound volumes (0..1).
        void (*set_master_volume)(struct ke_audio *self, float volume);

    } ke_audio;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_AUDIO_AUDIO_H_
