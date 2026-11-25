#ifndef KERNEL_ENGINE_RUNNER_WINDOW_RUNNER_WINDOW_PARTS_H_
#define KERNEL_ENGINE_RUNNER_WINDOW_RUNNER_WINDOW_PARTS_H_

#include <kernel_engine/runner/window/runner_window_create.h>
#include <kernel_engine/assembly/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_runner_window contains: `runner_window`, providing ke_runner, with the slots `scheduler` and
 * `window`.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_RUNNER_WINDOW_API const ke_part *ke_runner_window_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
