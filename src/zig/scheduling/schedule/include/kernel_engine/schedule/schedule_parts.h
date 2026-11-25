#ifndef KERNEL_ENGINE_SCHEDULE_SCHEDULE_PARTS_H_
#define KERNEL_ENGINE_SCHEDULE_SCHEDULE_PARTS_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/assembly/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_SCHEDULE_CREATE_API
#  ifdef KE_SCHEDULE_CREATE_EXPORT
#    define KE_SCHEDULE_CREATE_API KE_EXPORT
#  else
#    define KE_SCHEDULE_CREATE_API KE_IMPORT
#  endif
#endif

/**
 * Gives the parts ke_schedule contains: `schedule`, providing ke_schedule, ke_scheduler_executable and ke_schedule_set, with the slots `ecs` and `job`.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_SCHEDULE_CREATE_API const ke_part *ke_schedule_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
