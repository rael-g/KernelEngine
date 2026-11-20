#ifndef KERNEL_ENGINE_INPUT_DEFAULT_INPUT_DEFAULT_PARTS_H_
#define KERNEL_ENGINE_INPUT_DEFAULT_INPUT_DEFAULT_PARTS_H_

#include <kernel_engine/input/default/input_default_create.h>
#include <kernel_engine/assembly/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_input_default contains: `input_default`, providing ke_input.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_INPUT_DEFAULT_API const ke_part *ke_input_default_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
