#ifndef KERNEL_ENGINE_AUDIO_MINIAUDIO_AUDIO_MINIAUDIO_PARTS_H_
#define KERNEL_ENGINE_AUDIO_MINIAUDIO_AUDIO_MINIAUDIO_PARTS_H_

#include <kernel_engine/audio/miniaudio/miniaudio_audio.h>
#include <kernel_engine/part/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_audio_miniaudio contains: `audio_miniaudio`, providing ke_audio, with the slot `io`.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_AUDIO_MINIAUDIO_API const ke_part *ke_audio_miniaudio_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
