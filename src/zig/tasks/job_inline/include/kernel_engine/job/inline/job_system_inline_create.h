#ifndef KERNEL_ENGINE_JOB_INLINE_JOB_SYSTEM_INLINE_CREATE_H_
#define KERNEL_ENGINE_JOB_INLINE_JOB_SYSTEM_INLINE_CREATE_H_

#include <kernel_engine/configuration/settings.h>
#include <kernel_engine/common/export.h>
#include <kernel_engine/tasks/job_system.h>

#ifdef __cplusplus
extern "C" {
#endif


#ifndef KE_JOB_SYSTEM_INLINE_CREATE_API
#  ifdef KE_JOB_SYSTEM_INLINE_CREATE_EXPORT
#    define KE_JOB_SYSTEM_INLINE_CREATE_API KE_EXPORT
#  else
#    define KE_JOB_SYSTEM_INLINE_CREATE_API KE_IMPORT
#  endif
#endif

/**
 * Creates a job system that runs every job on the creating thread, when it is waited on or drained.
 * @param settings [borrowed] Read once. KE_JOB_SYSTEM_SETTING_WORKER_COUNT, default 0, the only value
 *        it accepts.
 * @param out_job_system [out] Receives the job system; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p settings or @p out_job_system, a worker_count other than zero, or another setting;
 *         KE_RESULT_OUT_OF_MEMORY.
 */
KE_JOB_SYSTEM_INLINE_CREATE_API ke_result ke_job_system_inline_create(ke_settings *settings, ke_job_system_handle *out_job_system);

#ifdef __cplusplus
}
#endif

#endif
