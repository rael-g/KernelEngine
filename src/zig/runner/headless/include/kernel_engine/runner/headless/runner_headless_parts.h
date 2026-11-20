#ifndef KERNEL_ENGINE_RUNNER_HEADLESS_RUNNER_HEADLESS_PARTS_H_
#define KERNEL_ENGINE_RUNNER_HEADLESS_RUNNER_HEADLESS_PARTS_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/assembly/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_RUNNER_HEADLESS_API
#  ifdef KE_RUNNER_HEADLESS_EXPORT
#    define KE_RUNNER_HEADLESS_API KE_EXPORT
#  else
#    define KE_RUNNER_HEADLESS_API KE_IMPORT
#  endif
#endif

/**
 * Gives the parts ke_runner_headless contains: `runner_headless`, providing ke_runner, with the slots `scheduler`
 * and `input`.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_RUNNER_HEADLESS_API const ke_part *ke_runner_headless_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
