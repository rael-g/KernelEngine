#ifndef KERNEL_ENGINE_SCHEDULER_SCHEDULER_PARTS_H_
#define KERNEL_ENGINE_SCHEDULER_SCHEDULER_PARTS_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/part/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_SCHEDULER_CREATE_API
#  ifdef KE_SCHEDULER_CREATE_EXPORT
#    define KE_SCHEDULER_CREATE_API KE_EXPORT
#  else
#    define KE_SCHEDULER_CREATE_API KE_IMPORT
#  endif
#endif

/**
 * Gives the parts ke_scheduler contains: `scheduler`, providing ke_scheduler, with the slots `job` and `async` and the cadence slots `startup`, `every_tick`, `fixed` and `shutdown`, each taking any number of ke_scheduler_executable, added in the order of their positions with the slot's cadence.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_SCHEDULER_CREATE_API const ke_part *ke_scheduler_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
