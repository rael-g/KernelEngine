#ifndef KERNEL_ENGINE_JOB_INLINE_JOB_SYSTEM_INLINE_PARTS_H_
#define KERNEL_ENGINE_JOB_INLINE_JOB_SYSTEM_INLINE_PARTS_H_

#include <kernel_engine/job/inline/job_system_inline_create.h>
#include <kernel_engine/assembly/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_job_system_inline contains: `job_system_inline`, providing ke_job_system.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_JOB_SYSTEM_INLINE_CREATE_API const ke_part *ke_job_system_inline_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
