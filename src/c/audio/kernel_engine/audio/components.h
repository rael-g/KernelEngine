#ifndef KERNEL_ENGINE_AUDIO_COMPONENTS_H_
#define KERNEL_ENGINE_AUDIO_COMPONENTS_H_

#include <kernel_engine/audio/audio.h>
#include <kernel_engine/spatial/transform.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_SOUND_MAX_PATH 256

    typedef enum ke_sound_release
    {
        KE_SOUND_RELEASE_KEEP      = 0, /**< The entity stays when the sound ends, ready to play again. */
        KE_SOUND_RELEASE_WHEN_DONE = 1, /**< The entity is destroyed when the sound ends. */
    } ke_sound_release;

    /// [table]
    /// [node:Sound,base:Node3D]
    /// One playback of an audio clip. The sound plays while @ref playing is set: setting it
    /// starts the clip from its beginning, clearing it stops the clip, and the clip reaching its
    /// end clears it. Two sounds of the same clip play at once, each on its own. The clip is
    /// loaded on the first update that sees the component and released on the first update in
    /// which the entity no longer holds it.
    typedef struct ke_sound_component
    {
        /// Path to the audio file, resolved against the project's base directory.
        char             path[KE_SOUND_MAX_PATH];
        float            volume; ///< [default:1] Linear gain, 0..1.
        float            pitch; ///< [default:1] Playback rate; 1 is the recorded pitch.
        /// Plays the clip again from its beginning each time it ends, until @ref playing is cleared.
        bool             loop;
        bool             playing;
        /// What happens to the entity when the clip ends.
        ke_sound_release release;

        /// [internal] The loaded clip, assigned when the component is reconciled. Callers do not
        /// write it.
        ke_audio_sound   clip;
        /// [internal] The playback in progress, assigned while the clip plays. Callers do not
        /// write it.
        ke_audio_voice   voice;
    } ke_sound_component;

#ifdef __cplusplus
}
#endif

#endif
