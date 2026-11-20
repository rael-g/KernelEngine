#ifndef KERNEL_ENGINE_AUDIO_MODULE_AUDIO_MODULE_PARTS_H_
#define KERNEL_ENGINE_AUDIO_MODULE_AUDIO_MODULE_PARTS_H_

#include <kernel_engine/audio/module/sound_module.h>
#include <kernel_engine/assembly/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_audio_module contains: `sound`, providing nothing, with the slots `ecs`, `audio` and
 * `post_update`, `post_update` the ke_schedule_set its systems join.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_AUDIO_MODULE_API const ke_part *ke_audio_module_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
