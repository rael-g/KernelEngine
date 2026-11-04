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

#define KE_AUDIO_PLAYER_MAX_PATH 256

    /// [table]
    /// [node:AudioPlayer,base:Node3D]
    /// A single audio clip, loaded from the path the scene declares and played on
    /// demand. Each node holds its own clip: two AudioPlayer children under the same
    /// parent are two clips, told apart by node name. The clip is loaded on the first update
    /// that sees the component and unloaded on the first update in which the entity no longer
    /// holds it.
    typedef struct ke_audio_player_component
    {
        /// Path to the audio file, resolved against the project's base directory.
        char  path[KE_AUDIO_PLAYER_MAX_PATH];
        float volume; ///< [default:1] Linear gain, 0..1.
        /// Set to play the clip once from its start at @ref volume; the next update plays it and
        /// clears the flag. A clip that is not loaded clears it without playing.
        bool  play_requested;

        /// [internal] The loaded clip, assigned when the component is reconciled. Callers do not
        /// write it.
        ke_audio_sound sound;
    } ke_audio_player_component;

#ifdef __cplusplus
}
#endif

#endif
