#ifndef KERNEL_ENGINE_SCHEDULER_SCHEDULER_CREATE_H_
#define KERNEL_ENGINE_SCHEDULER_SCHEDULER_CREATE_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/async/async.h>
#include <kernel_engine/job/job_system.h>
#include <kernel_engine/scheduler/scheduler.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef KE_SCHEDULER_CREATE_API
#  ifdef KE_SCHEDULER_CREATE_EXPORT
#    define KE_SCHEDULER_CREATE_API KE_EXPORT
#  else
#    define KE_SCHEDULER_CREATE_API KE_IMPORT
#  endif
#endif

/**
 * Creates a scheduler with no executable, which drains @p job_system and @p async, both borrowed
 * for its lifetime, at the start of every tick.
 * @param config [borrowed] Required; every field is read as given.
 * @param out_scheduler [out] Receives the scheduler; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p job_system, @p async, @p config or
 *         @p out_scheduler, or a fixed_dt or fixed_dt_max_accum not greater than zero;
 *         KE_RESULT_OUT_OF_MEMORY.
 */
KE_SCHEDULER_CREATE_API ke_result ke_scheduler_create(ke_job_system             *job_system,
                                                      ke_async                  *async,
                                                      const ke_scheduler_config *config,
                                                      ke_scheduler_handle       *out_scheduler);

#ifdef __cplusplus
}
#endif

#endif
