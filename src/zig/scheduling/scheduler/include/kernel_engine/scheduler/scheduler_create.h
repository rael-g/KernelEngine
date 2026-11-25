#ifndef KERNEL_ENGINE_SCHEDULER_SCHEDULER_CREATE_H_
#define KERNEL_ENGINE_SCHEDULER_SCHEDULER_CREATE_H_

#include <kernel_engine/configuration/settings.h>
#include <kernel_engine/common/export.h>
#include <kernel_engine/tasks/async.h>
#include <kernel_engine/tasks/job_system.h>
#include <kernel_engine/scheduling/scheduler.h>

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
 * @param settings [borrowed] Read once. KE_SCHEDULER_SETTING_FIXED_DT, default 1/60;
 *        KE_SCHEDULER_SETTING_FIXED_DT_MAX_ACCUM, default 0.25.
 * @param out_scheduler [out] Receives the scheduler; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p job_system, @p async, @p settings or
 *         @p out_scheduler, or a setting unknown, of another type or not greater than zero;
 *         KE_RESULT_OUT_OF_MEMORY.
 */
KE_SCHEDULER_CREATE_API ke_result ke_scheduler_create(ke_job_system             *job_system,
                                                      ke_async                  *async,
                                                      ke_settings               *settings,
                                                      ke_scheduler_handle       *out_scheduler);

#ifdef __cplusplus
}
#endif

#endif
