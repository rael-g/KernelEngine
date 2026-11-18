#ifndef KERNEL_ENGINE_SCHEDULE_SCHEDULE_CREATE_H_
#define KERNEL_ENGINE_SCHEDULE_SCHEDULE_CREATE_H_

#include <kernel_engine/settings/settings.h>
#include <kernel_engine/common/export.h>
#include <kernel_engine/job/job_system.h>
#include <kernel_engine/schedule/schedule.h>
#include <kernel_engine/ecs/ke_ecs.h>

#ifdef __cplusplus
extern "C" {
#endif


#ifndef KE_SCHEDULE_CREATE_API
#  ifdef KE_SCHEDULE_CREATE_EXPORT
#    define KE_SCHEDULE_CREATE_API KE_EXPORT
#  else
#    define KE_SCHEDULE_CREATE_API KE_IMPORT
#  endif
#endif

/**
 * Creates a schedule over @p ecs whose runs go to @p job_system, both borrowed for its lifetime.
 * @param settings [borrowed] Read once. `refuse_ambiguity`, a boolean, default false: an ambiguity
 *        between two writers fails the run instead of being logged.
 * @param out_schedule [out] Receives the schedule; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p ecs, @p job_system, @p settings or
 *         @p out_schedule, or a setting refused; KE_RESULT_OUT_OF_MEMORY.
 */
KE_SCHEDULE_CREATE_API ke_result ke_schedule_create(ke_ecs                   *ecs,
                                                    ke_job_system            *job_system,
                                                    struct ke_settings       *settings,
                                                    ke_schedule_handle       *out_schedule);

#ifdef __cplusplus
}
#endif

#endif
