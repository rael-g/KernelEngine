#ifndef KERNEL_ENGINE_AUDIO_COMPONENTS_H_
#define KERNEL_ENGINE_AUDIO_COMPONENTS_H_

#include <kernel_engine/spatial/transform.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

// Fixed-size, like ke_name_component's char name[64] elsewhere in this codebase:
// an ECS component is a C ABI struct, so a caller-provided ceiling is
// unavoidable here rather than a design choice. A path longer than this is
// truncated instead of overflowing.
#define KE_AUDIO_PLAYER_MAX_PATH 256

    /// [node:AudioPlayer,components:Node3D]
    /// A single audio clip, loaded from the path the scene declares and played on
    /// demand. The clip is one node's, not one system's: two AudioPlayer children
    /// under the same parent are two clips, told apart by node name.
    typedef struct ke_audio_player_component
    {
        /// Path to the audio file, resolved against the project's base directory.
        char  path[KE_AUDIO_PLAYER_MAX_PATH];
        float volume; ///< [default:1] Linear gain, 0..1.
    } ke_audio_player_component;

#define KE_COMPONENT_NAME_AUDIO_PLAYER "audio_player"

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_AUDIO_COMPONENTS_H_
